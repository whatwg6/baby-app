import { Directory, File, Paths } from 'expo-file-system';

import type { MediaType } from '../../domain/types';
import {
  normalizePrivateFilePath,
  normalizePrivateRoot,
  UnsafeMediaPathError,
} from './mediaPaths';

export interface StagedMedia {
  stagingPath: string;
  finalPath: string;
  mediaType: MediaType;
  thumbnailStagingPath: string | null;
  thumbnailFinalPath: string | null;
}

export interface MediaService {
  stage(input: { uri: string; mediaType: MediaType }): Promise<StagedMedia>;
  commit(staged: StagedMedia): Promise<{ filePath: string; thumbnailPath: string | null }>;
  rollback(staged: StagedMedia): Promise<void>;
  remove(paths: string[]): Promise<void>;
  removeOrphans(referencedPaths: string[]): Promise<void>;
}

export interface MediaFileSystem {
  readonly documentDirectory: string;
  availableDiskSpace(): number;
  fileSize(uri: string): number;
  ensureDirectory(uri: string): Promise<void>;
  copy(input: { from: string; to: string }): Promise<void>;
  move(input: { from: string; to: string }): Promise<void>;
  delete(uri: string): Promise<void>;
  exists(uri: string): boolean;
  list(directory: string): string[];
}

export type MediaServiceErrorCode = 'unsupported-format' | 'insufficient-space' | 'unsafe-path';

export class MediaServiceError extends Error {
  constructor(
    readonly code: MediaServiceErrorCode,
    message: string,
  ) {
    super(message);
    this.name = 'MediaServiceError';
  }
}

type MediaServiceDependencies = {
  fileSystem?: MediaFileSystem;
  createId?: () => string;
  createThumbnail?: (input: { from: string; to: string }) => Promise<void>;
};

const IMAGE_EXTENSIONS = new Set(['jpg', 'jpeg', 'png', 'heic', 'heif', 'webp']);
const VIDEO_EXTENSIONS = new Set(['mp4', 'mov', 'm4v']);

export function createMediaService(dependencies: MediaServiceDependencies = {}): MediaService {
  const fileSystem = dependencies.fileSystem ?? expoFileSystem;
  const createId = dependencies.createId ?? createUuid;
  const createThumbnail = dependencies.createThumbnail ?? createImageThumbnail;
  const stagingDirectory = normalizePrivateRoot(
    appendPath(fileSystem.documentDirectory, 'staging'),
  );
  const mediaDirectory = normalizePrivateRoot(
    appendPath(fileSystem.documentDirectory, 'media'),
  );

  const ownedPath = (path: string, root: string): string => {
    try {
      return normalizePrivateFilePath(path, root);
    } catch (cause) {
      if (cause instanceof UnsafeMediaPathError) {
        throw new MediaServiceError('unsafe-path', cause.message);
      }
      throw cause;
    }
  };

  const deleteExisting = async (path: string | null): Promise<void> => {
    if (path !== null && fileSystem.exists(path)) {
      await fileSystem.delete(path);
    }
  };

  const rollback = async (staged: StagedMedia): Promise<void> => {
    const stagingPath = ownedPath(staged.stagingPath, stagingDirectory);
    const thumbnailStagingPath = staged.thumbnailStagingPath === null
      ? null
      : ownedPath(staged.thumbnailStagingPath, stagingDirectory);
    await runAllCleanup([
      () => deleteExisting(stagingPath),
      () => deleteExisting(thumbnailStagingPath),
    ], '无法清理暂存媒体');
  };

  return {
    async stage(input) {
      const extension = supportedExtension(input.uri, input.mediaType);
      const sourceSize = fileSystem.fileSize(input.uri);
      const requiredSpace = input.mediaType === 'image' ? sourceSize * 2 : sourceSize;
      if (requiredSpace > fileSystem.availableDiskSpace()) {
        throw new MediaServiceError('insufficient-space', '设备存储空间不足，请清理后重试');
      }

      await fileSystem.ensureDirectory(stagingDirectory);
      await fileSystem.ensureDirectory(mediaDirectory);

      const id = createId();
      const stagingPath = appendPath(stagingDirectory, `${id}.${extension}`);
      const finalPath = appendPath(mediaDirectory, `${id}.${extension}`);
      const thumbnailStagingPath = input.mediaType === 'image'
        ? appendPath(stagingDirectory, `${id}-thumb.jpg`)
        : null;
      const thumbnailFinalPath = input.mediaType === 'image'
        ? appendPath(mediaDirectory, `${id}-thumb.jpg`)
        : null;
      const staged: StagedMedia = {
        stagingPath: ownedPath(stagingPath, stagingDirectory),
        finalPath: ownedPath(finalPath, mediaDirectory),
        mediaType: input.mediaType,
        thumbnailStagingPath: thumbnailStagingPath === null
          ? null
          : ownedPath(thumbnailStagingPath, stagingDirectory),
        thumbnailFinalPath: thumbnailFinalPath === null
          ? null
          : ownedPath(thumbnailFinalPath, mediaDirectory),
      };

      try {
        await fileSystem.copy({ from: input.uri, to: stagingPath });
        if (thumbnailStagingPath !== null) {
          await createThumbnail({ from: stagingPath, to: thumbnailStagingPath });
        }
        return staged;
      } catch (error) {
        return cleanupAndRethrow(error, [() => rollback(staged)], '媒体暂存与清理均失败');
      }
    },

    async commit(staged) {
      const safeStaged: StagedMedia = {
        ...staged,
        stagingPath: ownedPath(staged.stagingPath, stagingDirectory),
        finalPath: ownedPath(staged.finalPath, mediaDirectory),
        thumbnailStagingPath: staged.thumbnailStagingPath === null
          ? null
          : ownedPath(staged.thumbnailStagingPath, stagingDirectory),
        thumbnailFinalPath: staged.thumbnailFinalPath === null
          ? null
          : ownedPath(staged.thumbnailFinalPath, mediaDirectory),
      };
      let mainCommitted = false;
      let thumbnailCommitted = false;
      try {
        await fileSystem.move({ from: safeStaged.stagingPath, to: safeStaged.finalPath });
        mainCommitted = true;
        if (safeStaged.thumbnailStagingPath !== null && safeStaged.thumbnailFinalPath !== null) {
          await fileSystem.move({
            from: safeStaged.thumbnailStagingPath,
            to: safeStaged.thumbnailFinalPath,
          });
          thumbnailCommitted = true;
        }
        return { filePath: safeStaged.finalPath, thumbnailPath: safeStaged.thumbnailFinalPath };
      } catch (error) {
        return cleanupAndRethrow(error, [
          ...(mainCommitted ? [() => deleteExisting(safeStaged.finalPath)] : []),
          ...(thumbnailCommitted ? [() => deleteExisting(safeStaged.thumbnailFinalPath)] : []),
        ], '媒体提交与清理均失败');
      }
    },

    rollback,

    async remove(paths) {
      const ownedPaths = [...new Set(paths.map((path) => ownedPath(path, mediaDirectory)))];
      await runAllCleanup(
        ownedPaths.map((path) => () => deleteExisting(path)),
        '无法删除媒体文件',
      );
    },

    async removeOrphans(referencedPaths) {
      await fileSystem.ensureDirectory(stagingDirectory);
      await fileSystem.ensureDirectory(mediaDirectory);
      const referenced = new Set(
        referencedPaths.map((path) => ownedPath(path, mediaDirectory)),
      );
      const staleStagingPaths = fileSystem
        .list(stagingDirectory)
        .map((path) => ownedPath(path, stagingDirectory));
      const orphanPaths = fileSystem
        .list(mediaDirectory)
        .map((path) => ownedPath(path, mediaDirectory))
        .filter((path) => !referenced.has(path));
      await runAllCleanup(
        [...staleStagingPaths, ...orphanPaths].map((path) => () => deleteExisting(path)),
        '无法清理孤立媒体',
      );
    },
  };
}

function supportedExtension(uri: string, mediaType: MediaType): string {
  const match = /\.([a-zA-Z0-9]+)(?:[?#].*)?$/.exec(uri);
  const extension = match?.[1]?.toLowerCase() ?? '';
  const supported = mediaType === 'image' ? IMAGE_EXTENSIONS : VIDEO_EXTENSIONS;
  if (!supported.has(extension)) {
    throw new MediaServiceError('unsupported-format', '不支持此媒体格式');
  }
  return extension === 'jpeg' ? 'jpg' : extension;
}

function appendPath(directory: string, name: string): string {
  return `${directory.replace(/\/+$/, '')}/${name}`;
}

function createUuid(): string {
  if (globalThis.crypto !== undefined && typeof globalThis.crypto.randomUUID === 'function') {
    return globalThis.crypto.randomUUID();
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (character) => {
    const random = Math.floor(Math.random() * 16);
    const value = character === 'x' ? random : (random & 0x3) | 0x8;
    return value.toString(16);
  });
}

async function cleanupAndRethrow(
  primaryError: unknown,
  tasks: Array<() => Promise<void>>,
  message: string,
): Promise<never> {
  const cleanupErrors = await collectCleanupErrors(tasks);
  if (cleanupErrors.length > 0) {
    throw new AggregateError([primaryError, ...cleanupErrors], message);
  }
  throw primaryError;
}

async function runAllCleanup(
  tasks: Array<() => Promise<void>>,
  message: string,
): Promise<void> {
  const errors = await collectCleanupErrors(tasks);
  if (errors.length > 0) {
    throw new AggregateError(errors, message);
  }
}

async function collectCleanupErrors(tasks: Array<() => Promise<void>>): Promise<unknown[]> {
  const results = await Promise.allSettled(tasks.map((task) => task()));
  return results.flatMap((result) => result.status === 'rejected' ? [result.reason] : []);
}

const expoFileSystem: MediaFileSystem = {
  get documentDirectory() {
    return Paths.document.uri;
  },
  availableDiskSpace: () => Paths.availableDiskSpace,
  fileSize: (uri) => new File(uri).size,
  async ensureDirectory(uri) {
    new Directory(uri).create({ idempotent: true, intermediates: true });
  },
  async copy(input) {
    await new File(input.from).copy(new File(input.to));
  },
  async move(input) {
    await new File(input.from).move(new File(input.to));
  },
  async delete(uri) {
    new File(uri).delete();
  },
  exists: (uri) => new File(uri).exists,
  list: (directory) => {
    const target = new Directory(directory);
    return target.exists
      ? target.list().filter((entry) => entry instanceof File).map((file) => file.uri)
      : [];
  },
};

async function createImageThumbnail(input: { from: string; to: string }): Promise<void> {
  const { ImageManipulator, SaveFormat } = await import('expo-image-manipulator');
  const context = ImageManipulator.manipulate(input.from).resize({ width: 480 });
  const image = await context.renderAsync();
  const temporary = await image.saveAsync({ compress: 0.75, format: SaveFormat.JPEG });
  const temporaryFile = new File(temporary.uri);
  try {
    await temporaryFile.copy(new File(input.to));
  } finally {
    if (temporaryFile.exists) {
      temporaryFile.delete();
    }
  }
}

let defaultMediaService: MediaService | null = null;

function getDefaultMediaService(): MediaService {
  defaultMediaService ??= createMediaService();
  return defaultMediaService;
}

export const mediaService: MediaService = {
  stage: (input) => getDefaultMediaService().stage(input),
  commit: (staged) => getDefaultMediaService().commit(staged),
  rollback: (staged) => getDefaultMediaService().rollback(staged),
  remove: (paths) => getDefaultMediaService().remove(paths),
  removeOrphans: (paths) => getDefaultMediaService().removeOrphans(paths),
};
