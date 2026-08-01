import { Directory, File, Paths } from 'expo-file-system';
import type { SQLiteDatabase } from 'expo-sqlite';

import type { DatabaseManager } from '../../data/database';
import type { BabyRepository, RecordRepository } from '../../data/repositories';
import { migrateDatabase } from '../../data/migrations';
import type { MediaService } from '../media/mediaService';
import { parseBackupManifest, type BackupManifestV1 } from './backupManifest';

export interface BackupArchiveEntry {
  path: string;
  compressedSize: number;
  uncompressedSize: number;
  isDirectory: boolean;
  isSymbolicLink: boolean;
}

export interface BackupArchive {
  listEntries(sourcePath: string): Promise<BackupArchiveEntry[]>;
  zip(sourceDirectory: string, targetPath: string): Promise<void>;
  unzip(sourcePath: string, targetDirectory: string): Promise<void>;
}

export interface BackupFileSystem {
  readonly cacheDirectory: string;
  readonly documentDirectory: string;
  availableDiskSpace(): number;
  exists(path: string): boolean;
  size(path: string): number;
  readBytes(path: string): Promise<Uint8Array>;
  readText(path: string): Promise<string>;
  writeText(path: string, value: string): Promise<void>;
  ensureDirectory(path: string): Promise<void>;
  copyFile(source: string, target: string): Promise<void>;
  move(source: string, target: string): Promise<void>;
  delete(path: string): Promise<void>;
  list(directory: string): Array<{ path: string; modifiedAt: number }>;
}

export interface BackupSharing {
  isAvailable(): Promise<boolean>;
  share(path: string): Promise<void>;
}

export interface BackupExportResult {
  archivePath: string;
  shared: boolean;
  cleanupWarning?: string;
}

export type BackupRestoreResult =
  | { status: 'cancelled' }
  | { status: 'restored'; cleanupWarning?: string };

export interface BackupClearResult {
  cleanupPending: boolean;
  warning?: string;
}

export interface BackupService {
  export(): Promise<BackupExportResult>;
  inspect(archivePath: string): Promise<BackupManifestV1>;
  restore(archivePath?: string): Promise<BackupRestoreResult>;
  clear(): Promise<BackupClearResult>;
}

export type BackupServiceStage =
  | 'select'
  | 'archive'
  | 'manifest'
  | 'files'
  | 'integrity'
  | 'replace'
  | 'share'
  | 'cleanup';

export class BackupServiceError extends Error {
  constructor(
    readonly stage: BackupServiceStage,
    message: string,
    readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'BackupServiceError';
  }
}

type BackupServiceDependencies = {
  database: DatabaseManager;
  babies: BabyRepository;
  records: RecordRepository;
  media: MediaService;
  fileSystem?: BackupFileSystem;
  archive?: BackupArchive;
  sharing?: BackupSharing;
  hashFile?(path: string): Promise<string>;
  validateDatabase?(
    databasePath: string,
    restoredMedia: ReadonlyMap<string, string>,
  ): Promise<void>;
  pickArchive?(): Promise<string | null>;
  createId?(): string;
  now?(): Date;
};

type InspectedBackup = {
  archivePath: string;
  extractionDirectory: string;
  manifest: BackupManifestV1;
  restoredMedia: Map<string, string>;
};

type Replacement = {
  databasePath: string;
  databaseRollbackPath: string;
  databaseCandidatePath: string;
  mediaPath: string;
  mediaRollbackPath: string;
  mediaCandidatePath: string;
  databaseSidecars: Array<{ path: string; rollbackPath: string }>;
};

const EXPORT_EXPIRY_MS = 24 * 60 * 60 * 1000;
const DATABASE_ARCHIVE_PATH = 'database/app.db' as const;
const MANIFEST_ARCHIVE_PATH = 'manifest.json';

export function createBackupService(dependencies: BackupServiceDependencies): BackupService {
  const fileSystem = dependencies.fileSystem ?? expoBackupFileSystem;
  const archive = dependencies.archive ?? createNativeArchive(fileSystem);
  const sharing = dependencies.sharing ?? nativeSharing;
  const hashFile = dependencies.hashFile ?? ((path) => sha256File(path, fileSystem));
  const validateDatabase = dependencies.validateDatabase ?? validateSQLiteDatabaseFile;
  const pickArchive = dependencies.pickArchive ?? pickBackupArchive;
  const createId = dependencies.createId ?? createUuid;
  const now = dependencies.now ?? (() => new Date());
  const mediaDirectory = joinPath(fileSystem.documentDirectory, 'media');
  const workRoot = joinPath(fileSystem.cacheDirectory, 'backup-work');
  const exportRoot = joinPath(fileSystem.cacheDirectory, 'backup-exports');

  const inspectIntoWorkDirectory = async (
    archivePath: string,
    operationId: string,
  ): Promise<InspectedBackup> => {
    const operationDirectory = joinPath(workRoot, operationId);
    if (fileSystem.exists(operationDirectory)) {
      await fileSystem.delete(operationDirectory);
    }
    let entries: BackupArchiveEntry[];
    try {
      entries = await archive.listEntries(archivePath);
      validateArchiveEntries(entries, fileSystem.availableDiskSpace());
    } catch (cause) {
      throw asBackupError('archive', '备份压缩包结构不安全或已损坏', cause);
    }

    const extractionDirectory = joinPath(workRoot, `${operationId}/extracted`);
    await fileSystem.ensureDirectory(extractionDirectory);
    try {
      await archive.unzip(archivePath, extractionDirectory);
    } catch (cause) {
      throw asBackupError('archive', '无法解压备份文件', cause);
    }

    let manifest: BackupManifestV1;
    try {
      const rawManifest = await fileSystem.readText(
        archiveFilePath(extractionDirectory, MANIFEST_ARCHIVE_PATH),
      );
      manifest = parseBackupManifest(JSON.parse(rawManifest) as unknown);
      validateManifestPaths(manifest);
    } catch (cause) {
      throw asBackupError('manifest', '备份清单格式或版本不受支持', cause);
    }

    try {
      verifyEntrySet(entries, manifest);
      const databasePath = archiveFilePath(extractionDirectory, manifest.database.path);
      await verifyFile(databasePath, undefined, manifest.database.sha256, fileSystem, hashFile);

      const restoredMedia = new Map<string, string>();
      for (const mediaEntry of manifest.media) {
        const extractedPath = archiveFilePath(extractionDirectory, mediaEntry.path);
        await verifyFile(
          extractedPath,
          mediaEntry.size,
          mediaEntry.sha256,
          fileSystem,
          hashFile,
        );
        restoredMedia.set(
          mediaEntry.path,
          archiveFilePath(fileSystem.documentDirectory, mediaEntry.path),
        );
      }

      try {
        await validateDatabase(databasePath, restoredMedia);
      } catch (cause) {
        throw asBackupError('integrity', '备份数据库完整性校验失败', cause);
      }

      return {
        archivePath,
        extractionDirectory,
        manifest,
        restoredMedia,
      };
    } catch (cause) {
      if (cause instanceof BackupServiceError) {
        throw cause;
      }
      throw asBackupError('files', '备份文件缺失或校验不一致', cause);
    }
  };

  return {
    async export() {
      const operationId = safeOperationId(createId());
      const operationDirectory = joinPath(workRoot, `export-${operationId}`);
      const archivePath = joinPath(
        exportRoot,
        `baby-growth-${fileNameTimestamp(now())}-${operationId}.babygrowth.zip`,
      );
      let primaryError: unknown;
      let archiveCreated = false;
      let result: BackupExportResult | undefined;
      try {
        if (fileSystem.exists(operationDirectory)) {
          await fileSystem.delete(operationDirectory);
        }
        await fileSystem.ensureDirectory(operationDirectory);
        await fileSystem.ensureDirectory(joinPath(operationDirectory, 'database'));
        await fileSystem.ensureDirectory(joinPath(operationDirectory, 'media'));
        await fileSystem.ensureDirectory(exportRoot);
        const referencedMedia = await collectReferencedMedia(
          dependencies.babies,
          dependencies.records,
          mediaDirectory,
        );

        await dependencies.database.withClosedDatabase(async (databasePath) => {
          const snapshotPath = archiveFilePath(operationDirectory, DATABASE_ARCHIVE_PATH);
          if (!fileSystem.exists(databasePath)) {
            throw new BackupServiceError('files', '找不到当前数据库文件');
          }
          await fileSystem.copyFile(databasePath, snapshotPath);

          const mediaManifest: BackupManifestV1['media'] = [];
          for (const item of referencedMedia) {
            if (!fileSystem.exists(item.sourcePath)) {
              throw new BackupServiceError('files', `找不到媒体文件：${item.sourcePath}`);
            }
            const targetPath = archiveFilePath(operationDirectory, item.archivePath);
            await fileSystem.copyFile(item.sourcePath, targetPath);
            mediaManifest.push({
              path: item.archivePath,
              sha256: await hashFile(targetPath),
              size: fileSystem.size(targetPath),
            });
          }

          const manifest: BackupManifestV1 = {
            format: 'baby-growth-backup',
            version: 1,
            createdAt: now().toISOString(),
            database: {
              path: DATABASE_ARCHIVE_PATH,
              sha256: await hashFile(snapshotPath),
            },
            media: mediaManifest,
          };
          await fileSystem.writeText(
            archiveFilePath(operationDirectory, MANIFEST_ARCHIVE_PATH),
            JSON.stringify(manifest, null, 2),
          );
        });

        await archive.zip(operationDirectory, archivePath);
        archiveCreated = true;
        const shared = await sharing.isAvailable();
        if (shared) {
          try {
            await sharing.share(archivePath);
          } catch (cause) {
            throw asBackupError('share', `备份已保留在 ${archivePath}，但无法打开分享面板`, cause);
          }
        }
        result = { archivePath, shared };
      } catch (cause) {
        primaryError = cause;
      }

      const cleanupErrors = await collectCleanupErrors([
        ...(fileSystem.exists(operationDirectory)
          ? [() => fileSystem.delete(operationDirectory)]
          : []),
        ...(primaryError !== undefined && !archiveCreated && fileSystem.exists(archivePath)
          ? [() => fileSystem.delete(archivePath)]
          : []),
        ...expiredExportCleanupTasks(fileSystem, exportRoot, archivePath, now()),
      ]);
      if (primaryError !== undefined) {
        if (cleanupErrors.length > 0) {
          throw new AggregateError([primaryError, ...cleanupErrors], '备份导出失败且临时文件清理失败');
        }
        throw primaryError;
      }
      if (!archiveCreated || result === undefined) {
        throw new BackupServiceError('archive', '备份压缩包未生成');
      }
      if (cleanupErrors.length > 0) {
        result.cleanupWarning = cleanupMessage(cleanupErrors);
      }
      return result;
    },

    async inspect(archivePath) {
      const operationDirectory = joinPath(workRoot, `inspect-${safeOperationId(createId())}`);
      let inspection: InspectedBackup | undefined;
      let primaryError: unknown;
      try {
        inspection = await inspectIntoWorkDirectory(archivePath, basename(operationDirectory));
      } catch (cause) {
        primaryError = cause;
      }
      const cleanupErrors = fileSystem.exists(operationDirectory)
        ? await collectCleanupErrors([() => fileSystem.delete(operationDirectory)])
        : [];
      if (primaryError !== undefined || cleanupErrors.length > 0) {
        throwCombined(primaryError, cleanupErrors, '备份检查失败且临时文件清理失败');
      }
      if (inspection === undefined) {
        throw new BackupServiceError('manifest', '无法读取备份清单');
      }
      return inspection.manifest;
    },

    async restore(selectedArchivePath) {
      let archivePath = selectedArchivePath;
      if (archivePath === undefined) {
        try {
          archivePath = await pickArchive() ?? undefined;
        } catch (cause) {
          throw asBackupError('select', '无法选择备份文件', cause);
        }
      }
      if (archivePath === undefined) {
        return { status: 'cancelled' };
      }

      const operationId = safeOperationId(createId());
      const operationDirectory = joinPath(workRoot, operationId);
      let inspection: InspectedBackup | undefined;
      let replacement: Replacement | undefined;
      let primaryError: unknown;
      let cleanupWarning: string | undefined;
      let replacementCompleted = false;
      try {
        inspection = await inspectIntoWorkDirectory(archivePath, operationId);
        const mediaCandidatePath = `${mediaDirectory}.restore-${operationId}`;
        if (fileSystem.exists(mediaCandidatePath)) {
          await fileSystem.delete(mediaCandidatePath);
        }
        await fileSystem.ensureDirectory(mediaCandidatePath);
        for (const mediaEntry of inspection.manifest.media) {
          await fileSystem.copyFile(
            archiveFilePath(inspection.extractionDirectory, mediaEntry.path),
            joinPath(mediaCandidatePath, basename(mediaEntry.path)),
          );
        }

        await dependencies.database.withClosedDatabase(async (databasePath) => {
          replacement = replacementPaths(databasePath, mediaDirectory, operationId);
          try {
            await installReplacement(
              replacement,
              archiveFilePath(inspection!.extractionDirectory, DATABASE_ARCHIVE_PATH),
              fileSystem,
            );
            replacementCompleted = true;
          } catch (cause) {
            const rollbackErrors = await rollbackReplacement(replacement, fileSystem);
            if (rollbackErrors.length > 0) {
              throw new AggregateError(
                [cause, ...rollbackErrors],
                '恢复失败且旧数据回滚不完整',
              );
            }
            throw asBackupError('replace', '替换本地数据失败，旧数据已恢复', cause);
          }
        });
      } catch (cause) {
        primaryError = cause;
        if (replacementCompleted && replacement !== undefined) {
          const rollbackErrors = await rollbackReplacement(replacement, fileSystem);
          try {
            await dependencies.database.reopen();
          } catch (reopenError) {
            rollbackErrors.push(reopenError);
          }
          if (rollbackErrors.length > 0) {
            primaryError = new AggregateError(
              [cause, ...rollbackErrors],
              '数据库重开失败且旧数据回滚不完整',
            );
          }
        }
      }

      const cleanupTasks: Array<() => Promise<void>> = [];
      if (primaryError === undefined && replacement !== undefined) {
        cleanupTasks.push(...replacementCleanupTasks(replacement, fileSystem));
      }
      if (fileSystem.exists(operationDirectory)) {
        cleanupTasks.push(() => fileSystem.delete(operationDirectory));
      }
      const cleanupErrors = await collectCleanupErrors(cleanupTasks);
      if (primaryError !== undefined) {
        if (cleanupErrors.length > 0) {
          throw new AggregateError([primaryError, ...cleanupErrors], '恢复失败且临时文件清理失败');
        }
        throw primaryError;
      }
      if (cleanupErrors.length > 0) {
        cleanupWarning = cleanupMessage(cleanupErrors);
      }
      return { status: 'restored', ...(cleanupWarning === undefined ? {} : { cleanupWarning }) };
    },

    async clear() {
      const operationId = safeOperationId(createId());
      const referencedPaths = await collectReferencedPaths(
        dependencies.babies,
        dependencies.records,
      );
      let databasePath: string | undefined;
      let rollbackPath: string | undefined;
      let sidecarRollbacks: Array<{ path: string; rollbackPath: string }> = [];
      let databaseCleared = false;
      try {
        await dependencies.database.withClosedDatabase(async (currentDatabasePath) => {
          databasePath = currentDatabasePath;
          rollbackPath = `${currentDatabasePath}.rollback-clear-${operationId}`;
          sidecarRollbacks = databaseSidecarPaths(currentDatabasePath).map((path) => ({
            path,
            rollbackPath: `${path}.rollback-clear-${operationId}`,
          }));
          try {
            for (const sidecar of sidecarRollbacks) {
              if (fileSystem.exists(sidecar.path)) {
                await fileSystem.move(sidecar.path, sidecar.rollbackPath);
              }
            }
            await fileSystem.move(currentDatabasePath, rollbackPath);
            databaseCleared = true;
          } catch (cause) {
            const sidecarErrors = await restoreSidecarRollbacks(sidecarRollbacks, fileSystem);
            if (sidecarErrors.length > 0) {
              throw new AggregateError(
                [cause, ...sidecarErrors],
                '清空数据库失败且 SQLite 辅助文件回滚不完整',
              );
            }
            throw asBackupError('replace', '清空数据库失败，媒体尚未删除', cause);
          }
        });
      } catch (cause) {
        if (databaseCleared && databasePath !== undefined && rollbackPath !== undefined) {
          const rollbackErrors = await restoreSingleRollback(
            databasePath,
            rollbackPath,
            fileSystem,
          );
          rollbackErrors.push(...await restoreSidecarRollbacks(sidecarRollbacks, fileSystem, true));
          try {
            await dependencies.database.reopen();
          } catch (reopenError) {
            rollbackErrors.push(reopenError);
          }
          if (rollbackErrors.length > 0) {
            throw new AggregateError([cause, ...rollbackErrors], '清空失败且旧数据库回滚不完整');
          }
        }
        throw cause;
      }

      const cleanupErrors: unknown[] = [];
      if (rollbackPath !== undefined && fileSystem.exists(rollbackPath)) {
        try {
          await fileSystem.delete(rollbackPath);
        } catch (cause) {
          cleanupErrors.push(cause);
        }
      }
      cleanupErrors.push(...await collectCleanupErrors(
        sidecarRollbacks.flatMap((sidecar) => fileSystem.exists(sidecar.rollbackPath)
          ? [() => fileSystem.delete(sidecar.rollbackPath)]
          : []),
      ));

      if (referencedPaths.length > 0) {
        try {
          await dependencies.media.remove(referencedPaths);
        } catch (cause) {
          cleanupErrors.push(cause);
        }
      }
      try {
        await dependencies.media.removeOrphans([]);
      } catch (cause) {
        cleanupErrors.push(cause);
      }

      return {
        cleanupPending: cleanupErrors.length > 0,
        ...(cleanupErrors.length === 0 ? {} : { warning: cleanupMessage(cleanupErrors) }),
      };
    },
  };
}

export function readZipCentralDirectory(bytes: Uint8Array): BackupArchiveEntry[] {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const eocdOffset = findEndOfCentralDirectory(view);
  const diskNumber = readU16(view, eocdOffset + 4);
  const centralDisk = readU16(view, eocdOffset + 6);
  const diskEntries = readU16(view, eocdOffset + 8);
  const totalEntries = readU16(view, eocdOffset + 10);
  const centralSize = readU32(view, eocdOffset + 12);
  const centralOffset = readU32(view, eocdOffset + 16);
  const commentLength = readU16(view, eocdOffset + 20);
  if (eocdOffset + 22 + commentLength !== view.byteLength) {
    throw new Error('ZIP has trailing or truncated data after its central directory.');
  }
  if (diskNumber !== 0 || centralDisk !== 0 || diskEntries !== totalEntries) {
    throw new Error('Multi-disk ZIP archives are not supported.');
  }
  if (totalEntries === 0xffff || centralSize === 0xffffffff || centralOffset === 0xffffffff) {
    throw new Error('ZIP64 archives are not supported.');
  }
  if (centralOffset + centralSize !== eocdOffset) {
    throw new Error('ZIP central directory bounds are invalid.');
  }

  const entries: BackupArchiveEntry[] = [];
  let offset = centralOffset;
  for (let index = 0; index < totalEntries; index += 1) {
    ensureRange(view, offset, 46, 'central directory header');
    if (readU32(view, offset) !== 0x02014b50) {
      throw new Error('ZIP central directory header is invalid.');
    }
    const versionMadeBy = readU16(view, offset + 4);
    const flags = readU16(view, offset + 8);
    const compressedSize = readU32(view, offset + 20);
    const uncompressedSize = readU32(view, offset + 24);
    const nameLength = readU16(view, offset + 28);
    const extraLength = readU16(view, offset + 30);
    const entryCommentLength = readU16(view, offset + 32);
    const startDisk = readU16(view, offset + 34);
    const externalAttributes = readU32(view, offset + 38);
    const localHeaderOffset = readU32(view, offset + 42);
    if ((flags & 0x0001) !== 0) {
      throw new Error('Encrypted ZIP entries are not supported.');
    }
    if (compressedSize === 0xffffffff || uncompressedSize === 0xffffffff ||
        localHeaderOffset === 0xffffffff || startDisk !== 0) {
      throw new Error('ZIP64 entries are not supported.');
    }
    ensureRange(
      view,
      offset + 46,
      nameLength + extraLength + entryCommentLength,
      'central directory entry',
    );
    const path = decodeZipName(bytes, offset + 46, nameLength, flags);
    const localPath = readLocalHeaderPath(bytes, view, localHeaderOffset);
    if (localPath !== path) {
      throw new Error('ZIP local header path does not match its central directory entry.');
    }
    const dataStart = localHeaderDataStart(view, localHeaderOffset);
    if (dataStart + compressedSize > centralOffset) {
      throw new Error('ZIP entry data escapes its local file area.');
    }
    const platform = versionMadeBy >>> 8;
    const unixMode = externalAttributes >>> 16;
    entries.push({
      path,
      compressedSize,
      uncompressedSize,
      isDirectory: path.endsWith('/') || (externalAttributes & 0x10) !== 0,
      isSymbolicLink: platform === 3 && (unixMode & 0xf000) === 0xa000,
    });
    offset += 46 + nameLength + extraLength + entryCommentLength;
  }
  if (offset !== centralOffset + centralSize) {
    throw new Error('ZIP central directory entry count is inconsistent.');
  }
  return entries;
}

function validateArchiveEntries(entries: BackupArchiveEntry[], availableSpace: number): void {
  if (entries.length === 0) {
    throw new Error('ZIP archive is empty.');
  }
  const seen = new Set<string>();
  let expandedBytes = 0;
  for (const entry of entries) {
    validateArchivePath(entry.path, entry.isDirectory);
    const collisionKey = entry.path.normalize('NFC').toLocaleLowerCase('en-US');
    if (seen.has(collisionKey)) {
      throw new Error(`ZIP contains a duplicate entry: ${entry.path}`);
    }
    seen.add(collisionKey);
    if (entry.isSymbolicLink) {
      throw new Error(`ZIP symbolic links are not allowed: ${entry.path}`);
    }
    if (!Number.isSafeInteger(entry.compressedSize) || entry.compressedSize < 0 ||
        !Number.isSafeInteger(entry.uncompressedSize) || entry.uncompressedSize < 0) {
      throw new Error(`ZIP entry size is invalid: ${entry.path}`);
    }
    expandedBytes += entry.uncompressedSize;
    if (!Number.isSafeInteger(expandedBytes)) {
      throw new Error('ZIP expanded size is invalid.');
    }
    if (entry.isDirectory) {
      if (entry.path !== 'database/' && entry.path !== 'media/') {
        throw new Error(`ZIP directory is outside the backup format: ${entry.path}`);
      }
    } else if (entry.path !== MANIFEST_ARCHIVE_PATH &&
        entry.path !== DATABASE_ARCHIVE_PATH && !isFlatMediaArchivePath(entry.path)) {
      throw new Error(`ZIP entry is outside the backup format: ${entry.path}`);
    }
  }
  if (expandedBytes > availableSpace) {
    throw new Error('There is not enough space to inspect this backup.');
  }
}

function validateManifestPaths(manifest: BackupManifestV1): void {
  validateArchivePath(manifest.database.path, false);
  for (const entry of manifest.media) {
    validateArchivePath(entry.path, false);
    if (!isFlatMediaArchivePath(entry.path)) {
      throw new Error(`Media entry is outside the v1 media directory: ${entry.path}`);
    }
  }
}

function validateArchivePath(path: string, isDirectory: boolean): void {
  if (path.length === 0 || path.includes('\0') || path.includes('\\') ||
      path.startsWith('/') || /^[a-zA-Z]:/.test(path) || /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(path)) {
    throw new Error(`Archive entry path is unsafe: ${path}`);
  }
  if (isDirectory !== path.endsWith('/')) {
    throw new Error(`Archive entry kind does not match its path: ${path}`);
  }
  const contentPath = isDirectory ? path.slice(0, -1) : path;
  const segments = contentPath.split('/');
  if (segments.length === 0 || segments.some((segment) => (
    segment.length === 0 || segment === '.' || segment === '..'
  ))) {
    throw new Error(`Archive entry path is unsafe: ${path}`);
  }
}

function isFlatMediaArchivePath(path: string): boolean {
  return /^media\/[^/]+$/.test(path);
}

function verifyEntrySet(entries: BackupArchiveEntry[], manifest: BackupManifestV1): void {
  const actualFiles = entries
    .filter((entry) => !entry.isDirectory)
    .map((entry) => entry.path)
    .sort();
  const expectedFiles = [
    MANIFEST_ARCHIVE_PATH,
    manifest.database.path,
    ...manifest.media.map((entry) => entry.path),
  ].sort();
  if (actualFiles.length !== expectedFiles.length ||
      actualFiles.some((path, index) => path !== expectedFiles[index])) {
    throw new Error('ZIP entries do not match the backup manifest.');
  }
}

async function verifyFile(
  path: string,
  expectedSize: number | undefined,
  expectedHash: string,
  fileSystem: BackupFileSystem,
  hashFile: (path: string) => Promise<string>,
): Promise<void> {
  if (!fileSystem.exists(path)) {
    throw new Error(`Backup payload is missing: ${path}`);
  }
  if (expectedSize !== undefined && fileSystem.size(path) !== expectedSize) {
    throw new Error(`Backup payload size does not match: ${path}`);
  }
  const actualHash = (await hashFile(path)).toLowerCase();
  if (actualHash !== expectedHash.toLowerCase()) {
    throw new Error(`Backup payload hash does not match: ${path}`);
  }
}

async function collectReferencedMedia(
  babies: BabyRepository,
  records: RecordRepository,
  mediaDirectory: string,
): Promise<Array<{ sourcePath: string; archivePath: string }>> {
  const uniquePaths = await collectReferencedPaths(babies, records);
  return uniquePaths.map((sourcePath) => {
    const prefix = `${stripTrailingSlash(mediaDirectory)}/`;
    if (!sourcePath.startsWith(prefix)) {
      throw new BackupServiceError('files', `媒体路径不在 App 私有目录中：${sourcePath}`);
    }
    const relativePath = sourcePath.slice(prefix.length);
    const archivePath = `media/${relativePath}`;
    validateArchivePath(archivePath, false);
    if (!isFlatMediaArchivePath(archivePath)) {
      throw new BackupServiceError('files', `媒体路径不符合备份格式：${sourcePath}`);
    }
    return { sourcePath, archivePath };
  });
}

async function collectReferencedPaths(
  babies: BabyRepository,
  records: RecordRepository,
): Promise<string[]> {
  const [baby, timeline] = await Promise.all([babies.get(), records.list()]);
  const paths = [
    ...(baby?.avatarPath === null || baby?.avatarPath === undefined ? [] : [baby.avatarPath]),
    ...timeline.flatMap((record) => record.attachments.flatMap((attachment) => [
      attachment.filePath,
      ...(attachment.thumbnailPath === null ? [] : [attachment.thumbnailPath]),
    ])),
  ];
  return [...new Set(paths)].sort();
}

function replacementPaths(
  databasePath: string,
  mediaPath: string,
  operationId: string,
): Replacement {
  return {
    databasePath,
    databaseRollbackPath: `${databasePath}.rollback-${operationId}`,
    databaseCandidatePath: `${databasePath}.restore-${operationId}`,
    mediaPath,
    mediaRollbackPath: `${mediaPath}.rollback-${operationId}`,
    mediaCandidatePath: `${mediaPath}.restore-${operationId}`,
    databaseSidecars: databaseSidecarPaths(databasePath).map((path) => ({
      path,
      rollbackPath: `${path}.rollback-${operationId}`,
    })),
  };
}

async function installReplacement(
  replacement: Replacement,
  restoredDatabasePath: string,
  fileSystem: BackupFileSystem,
): Promise<void> {
  await fileSystem.copyFile(restoredDatabasePath, replacement.databaseCandidatePath);
  if (!fileSystem.exists(replacement.databasePath)) {
    throw new Error('Current database disappeared before replacement.');
  }
  for (const sidecar of replacement.databaseSidecars) {
    if (fileSystem.exists(sidecar.path)) {
      await fileSystem.move(sidecar.path, sidecar.rollbackPath);
    }
  }
  await fileSystem.move(replacement.databasePath, replacement.databaseRollbackPath);
  await fileSystem.move(replacement.databaseCandidatePath, replacement.databasePath);
  if (fileSystem.exists(replacement.mediaPath)) {
    await fileSystem.move(replacement.mediaPath, replacement.mediaRollbackPath);
  }
  await fileSystem.move(replacement.mediaCandidatePath, replacement.mediaPath);
}

async function rollbackReplacement(
  replacement: Replacement,
  fileSystem: BackupFileSystem,
): Promise<unknown[]> {
  const tasks: Array<() => Promise<void>> = [];
  if (fileSystem.exists(replacement.mediaRollbackPath)) {
    tasks.push(async () => {
      if (fileSystem.exists(replacement.mediaPath)) {
        await fileSystem.delete(replacement.mediaPath);
      }
      await fileSystem.move(replacement.mediaRollbackPath, replacement.mediaPath);
    });
  }
  if (fileSystem.exists(replacement.databaseRollbackPath)) {
    tasks.push(async () => {
      if (fileSystem.exists(replacement.databasePath)) {
        await fileSystem.delete(replacement.databasePath);
      }
      await fileSystem.move(replacement.databaseRollbackPath, replacement.databasePath);
    });
  }
  tasks.push(...replacement.databaseSidecars.flatMap((sidecar) => (
    fileSystem.exists(sidecar.rollbackPath)
      ? [async () => {
        if (fileSystem.exists(sidecar.path)) {
          await fileSystem.delete(sidecar.path);
        }
        await fileSystem.move(sidecar.rollbackPath, sidecar.path);
      }]
      : []
  )));
  if (fileSystem.exists(replacement.databaseCandidatePath)) {
    tasks.push(() => fileSystem.delete(replacement.databaseCandidatePath));
  }
  if (fileSystem.exists(replacement.mediaCandidatePath)) {
    tasks.push(() => fileSystem.delete(replacement.mediaCandidatePath));
  }
  return collectCleanupErrors(tasks);
}

function replacementCleanupTasks(
  replacement: Replacement,
  fileSystem: BackupFileSystem,
): Array<() => Promise<void>> {
  return [
    replacement.databaseRollbackPath,
    replacement.mediaRollbackPath,
    replacement.databaseCandidatePath,
    replacement.mediaCandidatePath,
    ...replacement.databaseSidecars.map((sidecar) => sidecar.rollbackPath),
  ].flatMap((path) => fileSystem.exists(path) ? [() => fileSystem.delete(path)] : []);
}

function databaseSidecarPaths(databasePath: string): string[] {
  return [`${databasePath}-wal`, `${databasePath}-shm`];
}

async function restoreSidecarRollbacks(
  sidecars: Array<{ path: string; rollbackPath: string }>,
  fileSystem: BackupFileSystem,
  deleteCurrent = false,
): Promise<unknown[]> {
  return collectCleanupErrors(sidecars.flatMap((sidecar) => {
    if (!fileSystem.exists(sidecar.rollbackPath)) {
      return [];
    }
    return [async () => {
      if (deleteCurrent && fileSystem.exists(sidecar.path)) {
        await fileSystem.delete(sidecar.path);
      }
      await fileSystem.move(sidecar.rollbackPath, sidecar.path);
    }];
  }));
}

async function restoreSingleRollback(
  databasePath: string,
  rollbackPath: string,
  fileSystem: BackupFileSystem,
): Promise<unknown[]> {
  return collectCleanupErrors([async () => {
    if (fileSystem.exists(databasePath)) {
      await fileSystem.delete(databasePath);
    }
    if (!fileSystem.exists(rollbackPath)) {
      throw new Error('The rollback database is missing.');
    }
    await fileSystem.move(rollbackPath, databasePath);
  }]);
}

function expiredExportCleanupTasks(
  fileSystem: BackupFileSystem,
  exportRoot: string,
  currentArchive: string,
  currentTime: Date,
): Array<() => Promise<void>> {
  if (!fileSystem.exists(exportRoot)) {
    return [];
  }
  const cutoff = currentTime.getTime() - EXPORT_EXPIRY_MS;
  return fileSystem.list(exportRoot).flatMap((entry) => (
    entry.path !== currentArchive && entry.modifiedAt < cutoff
      ? [() => fileSystem.delete(entry.path)]
      : []
  ));
}

async function collectCleanupErrors(tasks: Array<() => Promise<void>>): Promise<unknown[]> {
  const results = await Promise.allSettled(tasks.map((task) => task()));
  return results.flatMap((result) => result.status === 'rejected' ? [result.reason] : []);
}

function throwCombined(
  primaryError: unknown,
  cleanupErrors: unknown[],
  message: string,
): never {
  if (primaryError !== undefined && cleanupErrors.length === 0) {
    throw primaryError;
  }
  if (primaryError === undefined && cleanupErrors.length === 1) {
    throw asBackupError('cleanup', message, cleanupErrors[0]);
  }
  throw new AggregateError(
    [...(primaryError === undefined ? [] : [primaryError]), ...cleanupErrors],
    message,
  );
}

function cleanupMessage(errors: unknown[]): string {
  const details = errors.map(errorMessage).join('；');
  return `操作已完成，但清理仍待处理：${details}`;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function asBackupError(
  stage: BackupServiceStage,
  message: string,
  cause: unknown,
): BackupServiceError {
  return cause instanceof BackupServiceError ? cause : new BackupServiceError(stage, message, cause);
}

function archiveFilePath(root: string, archivePath: string): string {
  validateArchivePath(archivePath, false);
  const resolved = joinPath(root, archivePath);
  const prefix = `${stripTrailingSlash(root)}/`;
  if (!resolved.startsWith(prefix)) {
    throw new Error(`Archive path escapes extraction root: ${archivePath}`);
  }
  return resolved;
}

function joinPath(root: string, path: string): string {
  return `${stripTrailingSlash(root)}/${path.replace(/^\/+/, '')}`;
}

function stripTrailingSlash(path: string): string {
  return path.replace(/\/+$/, '');
}

function basename(path: string): string {
  return path.slice(path.lastIndexOf('/') + 1);
}

function parentPath(path: string): string {
  return path.slice(0, path.lastIndexOf('/'));
}

function fileNameTimestamp(date: Date): string {
  return date.toISOString().replace(/[:.]/g, '-');
}

function safeOperationId(id: string): string {
  const safe = id.replace(/[^a-zA-Z0-9_-]/g, '');
  return safe.length === 0 ? 'backup' : safe;
}

function createUuid(): string {
  if (globalThis.crypto !== undefined && typeof globalThis.crypto.randomUUID === 'function') {
    return globalThis.crypto.randomUUID();
  }
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function findEndOfCentralDirectory(view: DataView): number {
  const minimumOffset = Math.max(0, view.byteLength - (22 + 0xffff));
  for (let offset = view.byteLength - 22; offset >= minimumOffset; offset -= 1) {
    if (readU32(view, offset) === 0x06054b50) {
      return offset;
    }
  }
  throw new Error('ZIP end-of-central-directory record was not found.');
}

function readLocalHeaderPath(
  bytes: Uint8Array,
  view: DataView,
  offset: number,
): string {
  ensureRange(view, offset, 30, 'local header');
  if (readU32(view, offset) !== 0x04034b50) {
    throw new Error('ZIP local header is invalid.');
  }
  const flags = readU16(view, offset + 6);
  if ((flags & 0x0001) !== 0) {
    throw new Error('Encrypted ZIP entries are not supported.');
  }
  const nameLength = readU16(view, offset + 26);
  const extraLength = readU16(view, offset + 28);
  ensureRange(view, offset + 30, nameLength + extraLength, 'local header name');
  return decodeZipName(bytes, offset + 30, nameLength, flags);
}

function localHeaderDataStart(view: DataView, offset: number): number {
  ensureRange(view, offset, 30, 'local header');
  return offset + 30 + readU16(view, offset + 26) + readU16(view, offset + 28);
}

function decodeZipName(
  bytes: Uint8Array,
  offset: number,
  length: number,
  flags: number,
): string {
  const nameBytes = bytes.subarray(offset, offset + length);
  if ((flags & 0x0800) === 0) {
    if (nameBytes.some((value) => value > 0x7f)) {
      throw new Error('Non-UTF-8 ZIP entry names are not supported.');
    }
    return String.fromCharCode(...nameBytes);
  }
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(nameBytes);
  } catch (cause) {
    throw new Error('ZIP entry name is not valid UTF-8.', { cause });
  }
}

function ensureRange(view: DataView, offset: number, length: number, label: string): void {
  if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(length) ||
      offset < 0 || length < 0 || offset + length > view.byteLength) {
    throw new Error(`ZIP ${label} is outside the archive.`);
  }
}

function readU16(view: DataView, offset: number): number {
  ensureRange(view, offset, 2, 'field');
  return view.getUint16(offset, true);
}

function readU32(view: DataView, offset: number): number {
  ensureRange(view, offset, 4, 'field');
  return view.getUint32(offset, true);
}

function createNativeArchive(fileSystem: BackupFileSystem): BackupArchive {
  return {
    async listEntries(sourcePath) {
      return readZipCentralDirectory(await fileSystem.readBytes(sourcePath));
    },
    async zip(sourceDirectory, targetPath) {
      const nativeArchive = await import('react-native-zip-archive');
      await nativeArchive.zip(toNativeFilePath(sourceDirectory), toNativeFilePath(targetPath));
    },
    async unzip(sourcePath, targetDirectory) {
      const nativeArchive = await import('react-native-zip-archive');
      await nativeArchive.unzip(
        toNativeFilePath(sourcePath),
        toNativeFilePath(targetDirectory),
        'UTF-8',
      );
    },
  };
}

const nativeSharing: BackupSharing = {
  async isAvailable() {
    const sharing = await import('expo-sharing');
    return sharing.isAvailableAsync();
  },
  async share(path) {
    const sharing = await import('expo-sharing');
    await sharing.shareAsync(path, {
      dialogTitle: '导出宝宝成长备份',
      mimeType: 'application/zip',
      UTI: 'public.zip-archive',
    });
  },
};

async function pickBackupArchive(): Promise<string | null> {
  const documentPicker = await import('expo-document-picker');
  const result = await documentPicker.getDocumentAsync({
    type: ['application/zip', 'application/octet-stream'],
    copyToCacheDirectory: true,
    multiple: false,
  });
  return result.canceled ? null : result.assets[0]?.uri ?? null;
}

async function sha256File(path: string, fileSystem: BackupFileSystem): Promise<string> {
  const crypto = await import('expo-crypto');
  const source = await fileSystem.readBytes(path);
  const data = new ArrayBuffer(source.byteLength);
  new Uint8Array(data).set(source);
  const digest = await crypto.digest(
    crypto.CryptoDigestAlgorithm.SHA256,
    data,
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, '0'))
    .join('');
}

export async function validateSQLiteDatabaseFile(
  databasePath: string,
  restoredMedia: ReadonlyMap<string, string>,
  openDatabase: (
    databaseName: string,
    options: { useNewConnection: true },
    directory: string,
  ) => Promise<SQLiteDatabase> = openTemporarySQLiteDatabase,
): Promise<void> {
  const database = await openDatabase(
    basename(databasePath),
    { useNewConnection: true },
    parentPath(databasePath),
  );
  let primaryError: unknown;
  try {
    await assertIntegrity(database);
    await migrateDatabase(database);
    await remapRestoredMedia(database, restoredMedia);
    await assertIntegrity(database);
    await database.execAsync('PRAGMA wal_checkpoint(TRUNCATE);');
  } catch (cause) {
    primaryError = cause;
  }
  try {
    await database.closeAsync();
  } catch (closeError) {
    if (primaryError !== undefined) {
      throw new AggregateError(
        [primaryError, closeError],
        '备份数据库校验失败且临时连接无法关闭',
      );
    }
    throw closeError;
  }
  if (primaryError !== undefined) {
    throw primaryError;
  }
}

async function openTemporarySQLiteDatabase(
  databaseName: string,
  options: { useNewConnection: true },
  directory: string,
): Promise<SQLiteDatabase> {
  const sqlite = await import('expo-sqlite');
  return sqlite.openDatabaseAsync(databaseName, options, directory);
}

async function assertIntegrity(database: SQLiteDatabase): Promise<void> {
  const row = await database.getFirstAsync<Record<string, unknown>>('PRAGMA integrity_check;');
  const result = row === null ? undefined : Object.values(row)[0];
  if (typeof result !== 'string' || result.toLowerCase() !== 'ok') {
    throw new Error(`SQLite integrity_check returned ${String(result)}.`);
  }
}

async function remapRestoredMedia(
  database: SQLiteDatabase,
  restoredMedia: ReadonlyMap<string, string>,
): Promise<void> {
  const byFileName = new Map<string, string>();
  for (const [archivePath, localPath] of restoredMedia) {
    const name = basename(archivePath);
    if (byFileName.has(name)) {
      throw new Error(`Backup media filename is duplicated: ${name}`);
    }
    byFileName.set(name, localPath);
  }

  const attachments = await database.getAllAsync<{
    id: string;
    file_path: string;
    thumbnail_path: string | null;
  }>('SELECT id, file_path, thumbnail_path FROM attachments;');
  for (const attachment of attachments) {
    const filePath = requireRestoredMediaPath(attachment.file_path, byFileName);
    const thumbnailPath = attachment.thumbnail_path === null
      ? null
      : requireRestoredMediaPath(attachment.thumbnail_path, byFileName);
    await database.runAsync(
      'UPDATE attachments SET file_path = ?, thumbnail_path = ? WHERE id = ?;',
      [filePath, thumbnailPath, attachment.id],
    );
  }

  const babies = await database.getAllAsync<{
    singleton: number;
    avatar_path: string | null;
  }>('SELECT singleton, avatar_path FROM baby;');
  for (const baby of babies) {
    if (baby.avatar_path !== null) {
      await database.runAsync(
        'UPDATE baby SET avatar_path = ? WHERE singleton = ?;',
        [requireRestoredMediaPath(baby.avatar_path, byFileName), baby.singleton],
      );
    }
  }
}

function requireRestoredMediaPath(
  storedPath: string,
  byFileName: ReadonlyMap<string, string>,
): string {
  const localPath = byFileName.get(basename(storedPath));
  if (localPath === undefined) {
    throw new Error(`Database references media absent from the backup: ${storedPath}`);
  }
  return localPath;
}

function toNativeFilePath(path: string): string {
  if (!path.startsWith('file://')) {
    return path;
  }
  try {
    return decodeURIComponent(path.slice('file://'.length));
  } catch (cause) {
    throw new Error(`File URI cannot be converted for ZIP access: ${path}`, { cause });
  }
}

const expoBackupFileSystem: BackupFileSystem = {
  get cacheDirectory() {
    return Paths.cache.uri;
  },
  get documentDirectory() {
    return Paths.document.uri;
  },
  availableDiskSpace: () => Paths.availableDiskSpace,
  exists: (path) => new File(path).exists || new Directory(path).exists,
  size: (path) => new File(path).size,
  readBytes: (path) => new File(path).bytes(),
  readText: (path) => new File(path).text(),
  async writeText(path, value) {
    const file = new File(path);
    file.create({ overwrite: true, intermediates: true });
    file.write(value);
  },
  async ensureDirectory(path) {
    new Directory(path).create({ idempotent: true, intermediates: true });
  },
  async copyFile(source, target) {
    await new File(source).copy(new File(target), { overwrite: true });
  },
  async move(source, target) {
    const sourceFile = new File(source);
    if (sourceFile.exists) {
      await sourceFile.move(new File(target), { overwrite: false });
      return;
    }
    const sourceDirectory = new Directory(source);
    if (!sourceDirectory.exists) {
      throw new Error(`Path does not exist: ${source}`);
    }
    await sourceDirectory.move(new Directory(target), { overwrite: false });
  },
  async delete(path) {
    const file = new File(path);
    if (file.exists) {
      file.delete();
      return;
    }
    const directory = new Directory(path);
    if (directory.exists) {
      directory.delete();
    }
  },
  list(directory) {
    const target = new Directory(directory);
    if (!target.exists) {
      return [];
    }
    return target.list().flatMap((entry) => entry instanceof File
      ? [{ path: entry.uri, modifiedAt: entry.lastModified ?? 0 }]
      : []);
  },
};
