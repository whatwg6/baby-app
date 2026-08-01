import { sha256 } from '@noble/hashes/sha2';
import { Directory, File, FileMode, Paths } from 'expo-file-system';
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
  openRead(path: string): Promise<BackupFileReader>;
  readText(path: string): Promise<string>;
  writeText(path: string, value: string): Promise<void>;
  ensureDirectory(path: string): Promise<void>;
  copyFile(source: string, target: string): Promise<void>;
  move(source: string, target: string): Promise<void>;
  delete(path: string): Promise<void>;
  list(directory: string): Array<{ path: string; modifiedAt: number }>;
}

export interface BackupFileReader {
  readonly size: number;
  read(offset: number, length: number): Promise<Uint8Array>;
  close(): Promise<void>;
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
  readSnapshotMediaPaths?(databasePath: string): Promise<string[]>;
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
  databaseRetired: boolean;
  mediaPath: string;
  mediaRollbackPath: string;
  mediaCandidatePath: string;
  mediaExisted: boolean;
  mediaRetired: boolean;
  databaseSidecars: RollbackFile[];
};

type RollbackFile = {
  path: string;
  rollbackPath: string;
  existed: boolean;
  retired: boolean;
};

const EXPORT_EXPIRY_MS = 24 * 60 * 60 * 1000;
const DATABASE_ARCHIVE_PATH = 'database/app.db' as const;
const MANIFEST_ARCHIVE_PATH = 'manifest.json';

export function createBackupService(dependencies: BackupServiceDependencies): BackupService {
  const fileSystem = dependencies.fileSystem ?? expoBackupFileSystem;
  const archive = dependencies.archive ?? createNativeArchive(fileSystem);
  const sharing = dependencies.sharing ?? nativeSharing;
  const hashFile = dependencies.hashFile ?? ((path) => sha256File(path, fileSystem));
  const readSnapshotMediaPaths = dependencies.readSnapshotMediaPaths ?? readSQLiteMediaPaths;
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
        await dependencies.database.withClosedDatabase(async (databasePath) => {
          const snapshotPath = archiveFilePath(operationDirectory, DATABASE_ARCHIVE_PATH);
          if (!fileSystem.exists(databasePath)) {
            throw new BackupServiceError('files', '找不到当前数据库文件');
          }
          await fileSystem.copyFile(databasePath, snapshotPath);
          const referencedMedia = mapReferencedMedia(
            await readSnapshotMediaPaths(snapshotPath),
            mediaDirectory,
          );
          for (const sidecarPath of databaseSidecarPaths(snapshotPath)) {
            if (fileSystem.exists(sidecarPath)) {
              await fileSystem.delete(sidecarPath);
            }
          }

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
      let mediaCandidatePath: string | undefined;
      let primaryError: unknown;
      let cleanupWarning: string | undefined;
      let replacementCompleted = false;
      try {
        inspection = await inspectIntoWorkDirectory(archivePath, operationId);
        mediaCandidatePath = `${mediaDirectory}.restore-${operationId}`;
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
          replacement = replacementPaths(databasePath, mediaDirectory, operationId, fileSystem);
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
              throw dependencies.database.markRecoveryRequired(new AggregateError(
                [cause, ...rollbackErrors],
                '恢复失败且旧数据回滚不完整；数据库已保持关闭',
              ));
            }
            throw asBackupError('replace', '替换本地数据失败，旧数据已恢复', cause);
          }
        });
      } catch (cause) {
        primaryError = cause;
        if (replacementCompleted && replacement !== undefined) {
          const rollbackErrors = await rollbackReplacement(replacement, fileSystem);
          if (rollbackErrors.length > 0) {
            primaryError = dependencies.database.markRecoveryRequired(new AggregateError(
              [cause, ...rollbackErrors],
              '数据库重开失败且旧数据回滚不完整；数据库已保持关闭',
            ));
          } else {
            try {
              await dependencies.database.reopen();
            } catch (reopenError) {
              primaryError = new AggregateError(
                [cause, reopenError],
                '恢复数据无法打开；旧数据已完整回滚，但数据库重开失败',
              );
            }
          }
        }
      }

      const cleanupTasks: Array<() => Promise<void>> = [];
      if (primaryError === undefined && replacement !== undefined) {
        cleanupTasks.push(...replacementCleanupTasks(replacement, fileSystem));
      }
      if (mediaCandidatePath !== undefined && fileSystem.exists(mediaCandidatePath)) {
        cleanupTasks.push(() => fileSystem.delete(mediaCandidatePath!));
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
      let sidecarRollbacks: RollbackFile[] = [];
      let databaseCleared = false;
      try {
        await dependencies.database.withClosedDatabase(async (currentDatabasePath) => {
          databasePath = currentDatabasePath;
          rollbackPath = `${currentDatabasePath}.rollback-clear-${operationId}`;
          sidecarRollbacks = databaseSidecarPaths(currentDatabasePath).map((path) => ({
            path,
            rollbackPath: `${path}.rollback-clear-${operationId}`,
            existed: fileSystem.exists(path),
            retired: false,
          }));
          try {
            for (const sidecar of sidecarRollbacks) {
              if (sidecar.existed) {
                await fileSystem.move(sidecar.path, sidecar.rollbackPath);
                sidecar.retired = true;
              }
            }
            await fileSystem.move(currentDatabasePath, rollbackPath);
            databaseCleared = true;
          } catch (cause) {
            const rollbackErrors = await rollbackDatabaseFileSet(
              currentDatabasePath,
              rollbackPath,
              databaseCleared,
              sidecarRollbacks,
              fileSystem,
            );
            if (rollbackErrors.length > 0) {
              throw dependencies.database.markRecoveryRequired(new AggregateError(
                [cause, ...rollbackErrors],
                '清空数据库失败且 SQLite 文件集回滚不完整；数据库已保持关闭',
              ));
            }
            throw asBackupError('replace', '清空数据库失败，媒体尚未删除', cause);
          }
        });
      } catch (cause) {
        if (databaseCleared && databasePath !== undefined && rollbackPath !== undefined) {
          const rollbackErrors = await rollbackDatabaseFileSet(
            databasePath,
            rollbackPath,
            databaseCleared,
            sidecarRollbacks,
            fileSystem,
          );
          if (rollbackErrors.length > 0) {
            throw dependencies.database.markRecoveryRequired(new AggregateError(
              [cause, ...rollbackErrors],
              '清空失败且旧数据库回滚不完整；数据库已保持关闭',
            ));
          }
          try {
            await dependencies.database.reopen();
          } catch (reopenError) {
            throw new AggregateError(
              [cause, reopenError],
              '清空失败；旧数据库已完整回滚，但数据库重开失败',
            );
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

export async function readZipCentralDirectory(
  reader: BackupFileReader,
): Promise<BackupArchiveEntry[]> {
  const tailLength = Math.min(reader.size, 22 + 0xffff);
  const tailOffset = reader.size - tailLength;
  const tail = await readExact(reader, tailOffset, tailLength, 'end record search');
  const relativeEocdOffset = findEndOfCentralDirectory(tail);
  const eocdOffset = tailOffset + relativeEocdOffset;
  const eocd = tail.subarray(relativeEocdOffset);
  const diskNumber = readU16(eocd, 4);
  const centralDisk = readU16(eocd, 6);
  const diskEntries = readU16(eocd, 8);
  const totalEntries = readU16(eocd, 10);
  const centralSize = readU32(eocd, 12);
  const centralOffset = readU32(eocd, 16);
  const commentLength = readU16(eocd, 20);
  if (eocdOffset + 22 + commentLength !== reader.size) {
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
    const header = await readExact(reader, offset, 46, 'central directory header');
    if (readU32(header, 0) !== 0x02014b50) {
      throw new Error('ZIP central directory header is invalid.');
    }
    const versionMadeBy = readU16(header, 4);
    const flags = readU16(header, 8);
    const compressionMethod = readU16(header, 10);
    const crc = readU32(header, 16);
    const compressedSize = readU32(header, 20);
    const uncompressedSize = readU32(header, 24);
    const nameLength = readU16(header, 28);
    const extraLength = readU16(header, 30);
    const entryCommentLength = readU16(header, 32);
    const startDisk = readU16(header, 34);
    const externalAttributes = readU32(header, 38);
    const localHeaderOffset = readU32(header, 42);
    if ((flags & 0x0001) !== 0) {
      throw new Error('Encrypted ZIP entries are not supported.');
    }
    if (compressedSize === 0xffffffff || uncompressedSize === 0xffffffff ||
        localHeaderOffset === 0xffffffff || startDisk !== 0) {
      throw new Error('ZIP64 entries are not supported.');
    }
    ensureFileRange(
      reader.size,
      offset + 46,
      nameLength + extraLength + entryCommentLength,
      'central directory entry',
    );
    const variable = await readExact(
      reader,
      offset + 46,
      nameLength + extraLength,
      'central directory name and extra field',
    );
    const nameBytes = variable.subarray(0, nameLength);
    const extraBytes = variable.subarray(nameLength);
    validateZipExtraFields(extraBytes, 'central');
    const path = decodeZipName(nameBytes, flags);
    const local = await readLocalHeader(reader, localHeaderOffset);
    if (local.path !== path) {
      throw new Error('ZIP local header path does not match its central directory entry.');
    }
    if (local.flags !== flags) {
      throw new Error('ZIP local header flags do not match its central directory entry.');
    }
    if (local.compressionMethod !== compressionMethod) {
      throw new Error('ZIP local header compression method does not match its central directory entry.');
    }
    if (local.crc !== crc) {
      throw new Error('ZIP local header CRC does not match its central directory entry.');
    }
    if (local.compressedSize !== compressedSize) {
      throw new Error('ZIP local header compressed size does not match its central directory entry.');
    }
    if (local.uncompressedSize !== uncompressedSize) {
      throw new Error('ZIP local header uncompressed size does not match its central directory entry.');
    }
    if (local.dataStart + compressedSize > centralOffset) {
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

function mapReferencedMedia(
  uniquePaths: string[],
  mediaDirectory: string,
): Array<{ sourcePath: string; archivePath: string }> {
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

async function readSQLiteMediaPaths(databasePath: string): Promise<string[]> {
  const database = await openTemporarySQLiteDatabase(
    basename(databasePath),
    { useNewConnection: true },
    parentPath(databasePath),
  );
  let rows: Array<{ path: string }> | undefined;
  let primaryError: unknown;
  try {
    rows = await database.getAllAsync<{ path: string }>(`
      SELECT avatar_path AS path FROM baby WHERE avatar_path IS NOT NULL
      UNION
      SELECT file_path AS path FROM attachments
      UNION
      SELECT thumbnail_path AS path FROM attachments WHERE thumbnail_path IS NOT NULL;
    `);
  } catch (cause) {
    primaryError = cause;
  }
  try {
    await database.closeAsync();
  } catch (closeError) {
    if (primaryError !== undefined) {
      throw new AggregateError(
        [primaryError, closeError],
        'Snapshot media scan failed and its SQLite connection could not close.',
      );
    }
    throw closeError;
  }
  if (primaryError !== undefined) {
    throw primaryError;
  }
  if (rows === undefined || rows.some((row) => typeof row.path !== 'string')) {
    throw new Error('Snapshot media scan returned an invalid path.');
  }
  return [...new Set(rows.map((row) => row.path))].sort();
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
  fileSystem: BackupFileSystem,
): Replacement {
  return {
    databasePath,
    databaseRollbackPath: `${databasePath}.rollback-${operationId}`,
    databaseCandidatePath: `${databasePath}.restore-${operationId}`,
    databaseRetired: false,
    mediaPath,
    mediaRollbackPath: `${mediaPath}.rollback-${operationId}`,
    mediaCandidatePath: `${mediaPath}.restore-${operationId}`,
    mediaExisted: fileSystem.exists(mediaPath),
    mediaRetired: false,
    databaseSidecars: databaseSidecarPaths(databasePath).map((path) => ({
      path,
      rollbackPath: `${path}.rollback-${operationId}`,
      existed: fileSystem.exists(path),
      retired: false,
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
    if (sidecar.existed) {
      await fileSystem.move(sidecar.path, sidecar.rollbackPath);
      sidecar.retired = true;
    }
  }
  await fileSystem.move(replacement.databasePath, replacement.databaseRollbackPath);
  replacement.databaseRetired = true;
  await fileSystem.move(replacement.databaseCandidatePath, replacement.databasePath);
  if (fileSystem.exists(replacement.mediaPath)) {
    await fileSystem.move(replacement.mediaPath, replacement.mediaRollbackPath);
    replacement.mediaRetired = true;
  }
  await fileSystem.move(replacement.mediaCandidatePath, replacement.mediaPath);
}

async function rollbackReplacement(
  replacement: Replacement,
  fileSystem: BackupFileSystem,
): Promise<unknown[]> {
  const errors: unknown[] = [];
  await restoreSidecarFileSet(replacement.databaseSidecars, fileSystem, errors);

  await restoreRollbackFile(
    replacement.databasePath,
    replacement.databaseRollbackPath,
    true,
    replacement.databaseRetired,
    fileSystem,
    errors,
  );

  if (replacement.mediaRetired || fileSystem.exists(replacement.mediaRollbackPath)) {
    await captureRollbackError(errors, async () => {
      if (fileSystem.exists(replacement.mediaPath)) {
        await fileSystem.delete(replacement.mediaPath);
      }
      if (!fileSystem.exists(replacement.mediaRollbackPath)) {
        throw new Error('The retired media rollback directory is missing.');
      }
      await fileSystem.move(replacement.mediaRollbackPath, replacement.mediaPath);
    });
  } else if (!replacement.mediaExisted && fileSystem.exists(replacement.mediaPath)) {
    await captureRollbackError(errors, () => fileSystem.delete(replacement.mediaPath));
  }

  if (fileSystem.exists(replacement.databaseCandidatePath)) {
    await captureRollbackError(
      errors,
      () => fileSystem.delete(replacement.databaseCandidatePath),
    );
  }
  if (fileSystem.exists(replacement.mediaCandidatePath)) {
    await captureRollbackError(
      errors,
      () => fileSystem.delete(replacement.mediaCandidatePath),
    );
  }

  verifyRollbackPath(
    replacement.databasePath,
    true,
    'database',
    fileSystem,
    errors,
  );
  verifyRollbackPath(
    replacement.mediaPath,
    replacement.mediaExisted,
    'media directory',
    fileSystem,
    errors,
  );
  verifySidecarFileSet(replacement.databaseSidecars, fileSystem, errors);
  verifyAbsentRollbackArtifacts([
    replacement.databaseRollbackPath,
    replacement.mediaRollbackPath,
    replacement.databaseCandidatePath,
    replacement.mediaCandidatePath,
    ...replacement.databaseSidecars.map((sidecar) => sidecar.rollbackPath),
  ], fileSystem, errors);
  return errors;
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

async function rollbackDatabaseFileSet(
  databasePath: string,
  rollbackPath: string,
  databaseRetired: boolean,
  sidecars: RollbackFile[],
  fileSystem: BackupFileSystem,
): Promise<unknown[]> {
  const errors: unknown[] = [];
  await restoreSidecarFileSet(sidecars, fileSystem, errors);
  await restoreRollbackFile(
    databasePath,
    rollbackPath,
    true,
    databaseRetired,
    fileSystem,
    errors,
  );
  verifyRollbackPath(databasePath, true, 'database', fileSystem, errors);
  verifySidecarFileSet(sidecars, fileSystem, errors);
  verifyAbsentRollbackArtifacts(
    [rollbackPath, ...sidecars.map((sidecar) => sidecar.rollbackPath)],
    fileSystem,
    errors,
  );
  return errors;
}

async function restoreSidecarFileSet(
  sidecars: RollbackFile[],
  fileSystem: BackupFileSystem,
  errors: unknown[],
): Promise<void> {
  for (const sidecar of sidecars) {
    if (sidecar.retired || fileSystem.exists(sidecar.rollbackPath)) {
      await captureRollbackError(errors, async () => {
        if (fileSystem.exists(sidecar.path)) {
          await fileSystem.delete(sidecar.path);
        }
        if (!fileSystem.exists(sidecar.rollbackPath)) {
          throw new Error(`The retired SQLite sidecar rollback is missing: ${sidecar.path}`);
        }
        await fileSystem.move(sidecar.rollbackPath, sidecar.path);
      });
    } else if (!sidecar.existed && fileSystem.exists(sidecar.path)) {
      await captureRollbackError(errors, () => fileSystem.delete(sidecar.path));
    }
  }
}

async function restoreRollbackFile(
  path: string,
  rollbackPath: string,
  originallyExisted: boolean,
  retired: boolean,
  fileSystem: BackupFileSystem,
  errors: unknown[],
): Promise<void> {
  if (retired || fileSystem.exists(rollbackPath)) {
    await captureRollbackError(errors, async () => {
      if (fileSystem.exists(path)) {
        await fileSystem.delete(path);
      }
      if (!fileSystem.exists(rollbackPath)) {
        throw new Error(`The retired rollback file is missing: ${path}`);
      }
      await fileSystem.move(rollbackPath, path);
    });
  } else if (!originallyExisted && fileSystem.exists(path)) {
    await captureRollbackError(errors, () => fileSystem.delete(path));
  }
}

async function captureRollbackError(
  errors: unknown[],
  task: () => Promise<void>,
): Promise<void> {
  try {
    await task();
  } catch (cause) {
    errors.push(cause);
  }
}

function verifySidecarFileSet(
  sidecars: RollbackFile[],
  fileSystem: BackupFileSystem,
  errors: unknown[],
): void {
  for (const sidecar of sidecars) {
    verifyRollbackPath(sidecar.path, sidecar.existed, 'SQLite sidecar', fileSystem, errors);
  }
}

function verifyRollbackPath(
  path: string,
  shouldExist: boolean,
  label: string,
  fileSystem: BackupFileSystem,
  errors: unknown[],
): void {
  if (fileSystem.exists(path) !== shouldExist) {
    errors.push(new Error(
      `Rollback ${label} state is incomplete at ${path}; expected ${shouldExist ? 'present' : 'absent'}.`,
    ));
  }
}

function verifyAbsentRollbackArtifacts(
  paths: string[],
  fileSystem: BackupFileSystem,
  errors: unknown[],
): void {
  for (const path of paths) {
    if (fileSystem.exists(path)) {
      errors.push(new Error(`Rollback artifact remains at ${path}.`));
    }
  }
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

function findEndOfCentralDirectory(bytes: Uint8Array): number {
  for (let offset = bytes.byteLength - 22; offset >= 0; offset -= 1) {
    if (readU32(bytes, offset) === 0x06054b50) {
      return offset;
    }
  }
  throw new Error('ZIP end-of-central-directory record was not found.');
}

async function readLocalHeader(
  reader: BackupFileReader,
  offset: number,
): Promise<{
  path: string;
  flags: number;
  compressionMethod: number;
  crc: number;
  compressedSize: number;
  uncompressedSize: number;
  dataStart: number;
}> {
  const header = await readExact(reader, offset, 30, 'local header');
  if (readU32(header, 0) !== 0x04034b50) {
    throw new Error('ZIP local header is invalid.');
  }
  const flags = readU16(header, 6);
  if ((flags & 0x0001) !== 0) {
    throw new Error('Encrypted ZIP entries are not supported.');
  }
  const compressionMethod = readU16(header, 8);
  const crc = readU32(header, 14);
  const compressedSize = readU32(header, 18);
  const uncompressedSize = readU32(header, 22);
  const nameLength = readU16(header, 26);
  const extraLength = readU16(header, 28);
  if (compressedSize === 0xffffffff || uncompressedSize === 0xffffffff) {
    throw new Error('ZIP64 local header sizes are not supported.');
  }
  const variable = await readExact(
    reader,
    offset + 30,
    nameLength + extraLength,
    'local header name and extra field',
  );
  validateZipExtraFields(variable.subarray(nameLength), 'local');
  return {
    path: decodeZipName(variable.subarray(0, nameLength), flags),
    flags,
    compressionMethod,
    crc,
    compressedSize,
    uncompressedSize,
    dataStart: offset + 30 + nameLength + extraLength,
  };
}

function decodeZipName(
  nameBytes: Uint8Array,
  flags: number,
): string {
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

function validateZipExtraFields(bytes: Uint8Array, location: string): void {
  let offset = 0;
  while (offset < bytes.length) {
    if (bytes.length - offset < 4) {
      throw new Error(`ZIP ${location} extra field header is truncated.`);
    }
    const headerId = readU16(bytes, offset);
    const dataLength = readU16(bytes, offset + 2);
    offset += 4;
    if (offset + dataLength > bytes.length) {
      throw new Error(`ZIP ${location} extra field data is truncated.`);
    }
    if (headerId === 0x0001) {
      throw new Error(`ZIP64 ${location} extra fields are not supported.`);
    }
    offset += dataLength;
  }
}

async function readExact(
  reader: BackupFileReader,
  offset: number,
  length: number,
  label: string,
): Promise<Uint8Array> {
  ensureFileRange(reader.size, offset, length, label);
  const bytes = await reader.read(offset, length);
  if (bytes.length !== length) {
    throw new Error(`ZIP ${label} is truncated.`);
  }
  return bytes;
}

function ensureFileRange(size: number, offset: number, length: number, label: string): void {
  if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(length) ||
      offset < 0 || length < 0 || offset + length > size) {
    throw new Error(`ZIP ${label} is outside the archive.`);
  }
}

function readU16(bytes: Uint8Array, offset: number): number {
  ensureFileRange(bytes.byteLength, offset, 2, 'field');
  return new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint16(offset, true);
}

function readU32(bytes: Uint8Array, offset: number): number {
  ensureFileRange(bytes.byteLength, offset, 4, 'field');
  return new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(offset, true);
}

function createNativeArchive(fileSystem: BackupFileSystem): BackupArchive {
  return {
    async listEntries(sourcePath) {
      return withBackupFileReader(
        fileSystem,
        sourcePath,
        (reader) => readZipCentralDirectory(reader),
      );
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

export async function sha256File(path: string, fileSystem: BackupFileSystem): Promise<string> {
  return withBackupFileReader(fileSystem, path, async (reader) => {
    const hash = sha256.create();
    const chunkSize = 1024 * 1024;
    for (let offset = 0; offset < reader.size; offset += chunkSize) {
      const length = Math.min(chunkSize, reader.size - offset);
      const chunk = await reader.read(offset, length);
      if (chunk.length !== length) {
        throw new Error(`File changed or became truncated while hashing: ${path}`);
      }
      hash.update(chunk);
    }
    return [...hash.digest()]
      .map((value) => value.toString(16).padStart(2, '0'))
      .join('');
  });
}

async function withBackupFileReader<T>(
  fileSystem: BackupFileSystem,
  path: string,
  work: (reader: BackupFileReader) => Promise<T>,
): Promise<T> {
  const reader = await fileSystem.openRead(path);
  if (!Number.isSafeInteger(reader.size) || reader.size < 0) {
    try {
      await reader.close();
    } catch {
      // The invalid reader size is the primary boundary failure.
    }
    throw new Error(`File reader returned an invalid size for ${path}.`);
  }
  let value: T | undefined;
  let primaryError: unknown;
  try {
    value = await work(reader);
  } catch (cause) {
    primaryError = cause;
  }
  try {
    await reader.close();
  } catch (closeError) {
    if (primaryError !== undefined) {
      throw new AggregateError(
        [primaryError, closeError],
        `File read failed and its handle could not close: ${path}`,
      );
    }
    throw closeError;
  }
  if (primaryError !== undefined) {
    throw primaryError;
  }
  return value as T;
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
  async openRead(path) {
    const handle = new File(path).open(FileMode.ReadOnly);
    const size = handle.size;
    if (size === null) {
      handle.close();
      throw new Error(`Unable to determine file size: ${path}`);
    }
    return {
      size,
      async read(offset, length) {
        if (handle.offset === null) {
          throw new Error(`File handle is closed: ${path}`);
        }
        handle.offset = offset;
        return handle.readBytes(length);
      },
      async close() {
        handle.close();
      },
    };
  },
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
