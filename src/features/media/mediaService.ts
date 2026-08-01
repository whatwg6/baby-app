import { Directory, File, Paths } from 'expo-file-system';

import type { BabyRepository, RecordRepository } from '../../data/repositories';
import type {
  MediaType,
  NewAttachmentInput,
  NewRecordInput,
  RecordDraft,
  TimelineRecord,
} from '../../domain/types';

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

export interface MediaCleanupIssue {
  scope: 'record' | 'avatar';
  paths: string[];
  cause: unknown;
}

export const CLEANUP_PENDING_MESSAGE = '已保存，旧媒体将在稍后清理';

type RecordMediaDependencies = {
  records: RecordRepository;
  media: MediaService;
  onCleanupPending?(issue: MediaCleanupIssue): void;
};

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

type MediaServiceDependencies = {
  fileSystem?: MediaFileSystem;
  createId?: () => string;
  createThumbnail?: (input: { from: string; to: string }) => Promise<void>;
};

export type MediaServiceErrorCode = 'unsupported-format' | 'insufficient-space';

export class MediaServiceError extends Error {
  constructor(
    readonly code: MediaServiceErrorCode,
    message: string,
  ) {
    super(message);
    this.name = 'MediaServiceError';
  }
}

const IMAGE_EXTENSIONS = new Set(['jpg', 'jpeg', 'png', 'heic', 'heif', 'webp']);
const VIDEO_EXTENSIONS = new Set(['mp4', 'mov', 'm4v']);

export function createMediaService(dependencies: MediaServiceDependencies = {}): MediaService {
  const fileSystem = dependencies.fileSystem ?? expoFileSystem;
  const createId = dependencies.createId ?? createUuid;
  const createThumbnail = dependencies.createThumbnail ?? createImageThumbnail;
  const stagingDirectory = appendPath(fileSystem.documentDirectory, 'staging');
  const mediaDirectory = appendPath(fileSystem.documentDirectory, 'media');

  const deleteExisting = async (path: string | null): Promise<void> => {
    if (path !== null && fileSystem.exists(path)) {
      await fileSystem.delete(path);
    }
  };

  const rollback = async (staged: StagedMedia): Promise<void> => {
    await runAllCleanup([
      () => deleteExisting(staged.stagingPath),
      () => deleteExisting(staged.thumbnailStagingPath),
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
        stagingPath,
        finalPath,
        mediaType: input.mediaType,
        thumbnailStagingPath,
        thumbnailFinalPath,
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
      let mainCommitted = false;
      let thumbnailCommitted = false;
      try {
        await fileSystem.move({ from: staged.stagingPath, to: staged.finalPath });
        mainCommitted = true;
        if (staged.thumbnailStagingPath !== null && staged.thumbnailFinalPath !== null) {
          await fileSystem.move({
            from: staged.thumbnailStagingPath,
            to: staged.thumbnailFinalPath,
          });
          thumbnailCommitted = true;
        }
        return { filePath: staged.finalPath, thumbnailPath: staged.thumbnailFinalPath };
      } catch (error) {
        return cleanupAndRethrow(error, [
          ...(mainCommitted ? [() => deleteExisting(staged.finalPath)] : []),
          ...(thumbnailCommitted ? [() => deleteExisting(staged.thumbnailFinalPath)] : []),
        ], '媒体提交与清理均失败');
      }
    },

    rollback,

    async remove(paths) {
      const ownedPaths = [...new Set(paths)].filter((path) => isInside(path, mediaDirectory));
      await runAllCleanup(
        ownedPaths.map((path) => () => deleteExisting(path)),
        '无法删除媒体文件',
      );
    },

    async removeOrphans(referencedPaths) {
      await fileSystem.ensureDirectory(stagingDirectory);
      await fileSystem.ensureDirectory(mediaDirectory);
      const referenced = new Set(referencedPaths);
      const staleStagingPaths = fileSystem
        .list(stagingDirectory)
        .filter((path) => isInside(path, stagingDirectory));
      const orphanPaths = fileSystem
        .list(mediaDirectory)
        .filter((path) => isInside(path, mediaDirectory) && !referenced.has(path));
      await runAllCleanup(
        [...staleStagingPaths, ...orphanPaths].map((path) => () => deleteExisting(path)),
        '无法清理孤立媒体',
      );
    },
  };
}

export async function saveRecordWithMedia(
  input: RecordDraft,
  dependencies: RecordMediaDependencies,
): Promise<TimelineRecord> {
  return persistRecordWithMedia('create', null, input, dependencies);
}

export async function updateRecordWithMedia(
  id: string,
  input: RecordDraft,
  dependencies: RecordMediaDependencies,
): Promise<TimelineRecord> {
  const previous = await dependencies.records.get(id);
  if (previous === null) {
    throw new Error(`Record ${id} was not found.`);
  }

  const saved = await persistRecordWithMedia('update', id, input, dependencies);
  const retainedPaths = new Set(attachmentPaths(saved));
  const removedPaths = attachmentPaths(previous).filter((path) => !retainedPaths.has(path));
  if (removedPaths.length > 0) {
    try {
      await dependencies.media.remove(removedPaths);
    } catch (cause) {
      dependencies.onCleanupPending?.({ scope: 'record', paths: removedPaths, cause });
    }
  }
  return saved;
}

export async function removeUnreferencedMedia(dependencies: {
  babies: BabyRepository;
  records: RecordRepository;
  media: MediaService;
}): Promise<void> {
  const [baby, records] = await Promise.all([
    dependencies.babies.get(),
    dependencies.records.list(),
  ]);
  const referencedPaths = [
    ...(baby?.avatarPath === null || baby?.avatarPath === undefined ? [] : [baby.avatarPath]),
    ...records.flatMap(attachmentPaths),
  ];
  await dependencies.media.removeOrphans(referencedPaths);
}

async function persistRecordWithMedia(
  operation: 'create' | 'update',
  id: string | null,
  draft: RecordDraft,
  dependencies: RecordMediaDependencies,
): Promise<TimelineRecord> {
  const stagedMedia: StagedMedia[] = [];
  const committedPaths: string[] = [];

  try {
    for (const attachment of draft.attachments) {
      if (attachment.kind === 'picked') {
        stagedMedia.push(await dependencies.media.stage({
          uri: attachment.sourceUri,
          mediaType: attachment.mediaType,
        }));
      }
    }
  } catch (error) {
    return cleanupAndRethrow(
      error,
      stagedMedia.map((staged) => () => dependencies.media.rollback(staged)),
      '媒体暂存与回滚均失败',
    );
  }

  const repositoryInput = toRepositoryInput(draft, stagedMedia);
  try {
    return await dependencies.records.withTransaction(async (transaction) => {
      const saved = operation === 'create'
        ? await transaction.create(repositoryInput)
        : await transaction.update(requireId(id), repositoryInput);

      for (const staged of stagedMedia) {
        const committed = await dependencies.media.commit(staged);
        committedPaths.push(committed.filePath);
        if (committed.thumbnailPath !== null) {
          committedPaths.push(committed.thumbnailPath);
        }
      }
      return saved;
    });
  } catch (error) {
    const cleanup = stagedMedia.map((staged) => () => dependencies.media.rollback(staged));
    if (committedPaths.length > 0) {
      cleanup.push(() => dependencies.media.remove(committedPaths));
    }
    return cleanupAndRethrow(error, cleanup, '记录保存与媒体清理均失败');
  }
}

function toRepositoryInput(draft: RecordDraft, stagedMedia: StagedMedia[]): NewRecordInput {
  let pickedIndex = 0;
  const attachments: NewAttachmentInput[] = draft.attachments.map((attachment) => {
    if (attachment.kind === 'existing') {
      return {
        id: attachment.id,
        mediaType: attachment.mediaType,
        filePath: attachment.filePath,
        thumbnailPath: attachment.thumbnailPath,
      };
    }

    const staged = stagedMedia[pickedIndex];
    pickedIndex += 1;
    if (staged === undefined) {
      throw new Error('Picked media was not staged.');
    }
    return {
      mediaType: attachment.mediaType,
      filePath: staged.finalPath,
      thumbnailPath: staged.thumbnailFinalPath,
    };
  });

  return {
    type: draft.type,
    occurredAt: draft.occurredAt,
    note: draft.note,
    details: draft.details,
    attachments,
  };
}

function attachmentPaths(record: TimelineRecord): string[] {
  return record.attachments.flatMap((attachment) => [
    attachment.filePath,
    ...(attachment.thumbnailPath === null ? [] : [attachment.thumbnailPath]),
  ]);
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

function isInside(path: string, directory: string): boolean {
  return path.startsWith(`${directory.replace(/\/+$/, '')}/`);
}

function requireId(id: string | null): string {
  if (id === null) {
    throw new Error('An update requires a record id.');
  }
  return id;
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
    return target.exists ? target.list().filter((entry) => entry instanceof File).map((file) => file.uri) : [];
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
