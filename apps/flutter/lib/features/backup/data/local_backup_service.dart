import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../data/database/database_lifecycle.dart';
import '../../../data/database/migrations.dart';
import '../../../domain/destructive_operation_gate.dart';
import '../domain/backup_manifest.dart';
import '../domain/backup_service.dart';

export '../domain/backup_service.dart'
    show
        BackupException,
        BackupReopenException,
        BackupRollbackException,
        BackupShareException;

typedef BackupPathRenamer =
    Future<void> Function(String source, String destination);
typedef BackupDirectoryDeleter = Future<void> Function(Directory directory);
typedef BackupArchiveCopyObserver = Future<void> Function(int copiedBytes);

enum BackupRestoreStep {
  beforeCurrentDatabaseMove,
  afterCurrentDatabaseMove,
  afterCurrentMediaMove,
  afterReplacementDatabaseMove,
  afterReplacementMediaMove,
  afterReplacementVerification,
}

class BackupArchiveLimits {
  const BackupArchiveLimits({
    this.maxArchiveBytes = 512 * 1024 * 1024,
    this.maxEntryBytes = 256 * 1024 * 1024,
    this.maxTotalBytes = 1024 * 1024 * 1024,
    this.maxEntries = 10000,
    this.maxManifestBytes = 1024 * 1024,
  });

  final int maxArchiveBytes;
  final int maxEntryBytes;
  final int maxTotalBytes;
  final int maxEntries;
  final int maxManifestBytes;
}

class LocalBackupService implements BackupService {
  LocalBackupService({
    required this.databaseLifecycle,
    required this.destructiveOperationGate,
    DatabaseFactory? databaseFactory,
    Future<Directory> Function()? applicationSupportDirectory,
    Future<Directory> Function()? inspectionDirectory,
    Future<void> Function(String path)? shareArchive,
    String Function()? createId,
    DateTime Function()? now,
    this.limits = const BackupArchiveLimits(),
    this.onRestoreStep,
    BackupPathRenamer? renamePath,
    BackupDirectoryDeleter? deleteDirectory,
    this.onArchiveCopyChunk,
  }) : _databaseFactory = databaseFactory ?? databaseFactorySqflitePlugin,
       _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory,
       _inspectionDirectory = inspectionDirectory ?? getTemporaryDirectory,
       _shareArchive = shareArchive ?? _share,
       _createId = createId ?? const Uuid().v4,
       _now = now ?? DateTime.now,
       _renamePath = renamePath ?? _rename,
       _deleteDirectory = deleteDirectory ?? _deleteDirectoryRecursively;

  static const archiveExtension = '.babygrowth.zip';
  static const manifestPath = 'manifest.json';
  static const databaseArchivePath = 'database/app.db';

  final DatabaseLifecycle databaseLifecycle;
  final DestructiveOperationGate destructiveOperationGate;
  final DatabaseFactory _databaseFactory;
  final Future<Directory> Function() _applicationSupportDirectory;
  final Future<Directory> Function() _inspectionDirectory;
  final Future<void> Function(String path) _shareArchive;
  final String Function() _createId;
  final DateTime Function() _now;
  final BackupArchiveLimits limits;
  final Future<void> Function(BackupRestoreStep step)? onRestoreStep;
  final BackupPathRenamer _renamePath;
  final BackupDirectoryDeleter _deleteDirectory;
  final BackupArchiveCopyObserver? onArchiveCopyChunk;
  final Map<BackupInspection, _InspectionBinding> _bindings =
      Map<BackupInspection, _InspectionBinding>.identity();

  @override
  Future<String> exportBackup() async {
    final supportRoot = await _validatedDirectory(
      await _applicationSupportDirectory(),
      create: true,
      label: '应用数据目录',
    );
    final exports = (await _childDirectory(
      supportRoot,
      'backup-exports',
      create: true,
    ))!;
    final workRoot = (await _childDirectory(
      supportRoot,
      'backup-work',
      create: true,
    ))!;
    final work = Directory(p.join(workRoot.path, _safeId()));
    await _createUniqueDirectory(work);
    final stagedDatabase = File(
      p.joinAll([work.path, ...databaseArchivePath.split('/')]),
    );
    await stagedDatabase.parent.create(recursive: true);

    String? completedArchive;
    String? partialArchive;
    try {
      late List<BackupFileEntry> fileEntries;
      late Map<String, String> sourceByArchivePath;
      await databaseLifecycle.withClosedDatabase<void>((databasePath) async {
        await _copyRegularFile(databasePath, stagedDatabase.path);
        final mediaPaths = await _referencedMediaPaths(stagedDatabase.path);
        fileEntries = <BackupFileEntry>[
          await _entryForFile(stagedDatabase.path, databaseArchivePath),
        ];
        sourceByArchivePath = <String, String>{
          databaseArchivePath: stagedDatabase.path,
        };
        for (final storedPath in mediaPaths) {
          final source = await _canonicalMediaSource(supportRoot, storedPath);
          final existing = sourceByArchivePath[source.archivePath];
          if (existing != null) {
            if (existing != source.sourcePath) {
              throw BackupException('多个媒体文件映射到同一个备份路径：${source.archivePath}');
            }
            continue;
          }
          final stagedPath = p.joinAll([
            work.path,
            ...source.archivePath.split('/'),
          ]);
          await File(stagedPath).parent.create(recursive: true);
          await _copyRegularFile(source.sourcePath, stagedPath);
          sourceByArchivePath[source.archivePath] = stagedPath;
          fileEntries.add(await _entryForFile(stagedPath, source.archivePath));
        }
      });

      fileEntries.sort((left, right) => left.path.compareTo(right.path));
      final databaseEntry = fileEntries.singleWhere(
        (entry) => entry.path == databaseArchivePath,
      );
      final mediaEntries = fileEntries
          .where((entry) => entry.path != databaseArchivePath)
          .toList(growable: false);
      final manifest = BackupManifestV1(
        createdAt: _now().toUtc().toIso8601String(),
        database: databaseEntry,
        media: mediaEntries,
      );
      final manifestBytes = utf8.encode(jsonEncode(manifest.toJson()));
      if (fileEntries.length + 1 > limits.maxEntries) {
        throw const BackupException('备份条目数量超过限制。');
      }
      if (manifestBytes.length > limits.maxManifestBytes ||
          manifestBytes.length > limits.maxEntryBytes) {
        throw const BackupException('备份清单超过大小限制。');
      }
      final totalBytes = fileEntries.fold<int>(
        manifestBytes.length,
        (total, entry) => total + entry.size,
      );
      if (totalBytes > limits.maxTotalBytes) {
        throw const BackupException('备份总大小超过限制。');
      }

      final timestamp = _now().toUtc().toIso8601String().replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      final archiveName =
          'baby-growth-$timestamp-${_safeId()}'
          '$archiveExtension';
      final finalPath = p.join(exports.path, archiveName);
      final temporaryPath = '$finalPath.partial';
      partialArchive = temporaryPath;
      final archive = Archive()
        ..addFile(ArchiveFile.bytes(manifestPath, manifestBytes));
      for (final entry in fileEntries) {
        archive.addFile(
          ArchiveFile.stream(
            entry.path,
            InputFileStream(sourceByArchivePath[entry.path]!),
          ),
        );
      }
      final output = OutputFileStream(temporaryPath);
      try {
        ZipEncoder().encodeStream(archive, output, autoClose: true);
      } finally {
        output.closeSync();
      }
      if (await File(temporaryPath).length() > limits.maxArchiveBytes) {
        await File(temporaryPath).delete();
        throw const BackupException('备份包超过大小限制。');
      }
      await _renamePath(temporaryPath, finalPath);
      completedArchive = finalPath;
    } catch (error) {
      if (error is BackupException) rethrow;
      throw BackupException('导出备份失败', error);
    } finally {
      if (partialArchive != null) {
        await _deletePathIfPresent(partialArchive);
      }
      await _deleteDirectoryIfPresent(work);
    }

    try {
      await _shareArchive(completedArchive);
    } catch (error) {
      throw BackupShareException(completedArchive, error);
    }
    return completedArchive;
  }

  @override
  Future<BackupInspection> inspect(String archivePath) async {
    Directory? temporary;
    Directory? archiveSnapshotDirectory;
    InputFileStream? archiveInput;
    try {
      if (!archivePath.endsWith(archiveExtension)) {
        throw const BackupException('备份文件扩展名无效。');
      }
      final sourceArchive = File(archivePath);
      if (await FileSystemEntity.type(archivePath, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const BackupException('备份文件不存在或不是普通文件。');
      }
      final inspectionRoot = await _validatedDirectory(
        await _inspectionDirectory(),
        create: true,
        label: '备份检查目录',
      );
      archiveSnapshotDirectory = Directory(
        p.join(inspectionRoot.path, 'baby-growth-archive-${_safeId()}'),
      );
      await _createUniqueDirectory(archiveSnapshotDirectory);
      final archiveFile = File(
        p.join(archiveSnapshotDirectory.path, 'source$archiveExtension'),
      );
      final archiveSnapshot = await _copyArchiveSnapshot(
        sourceArchive,
        archiveFile,
      );
      await _preflightZipDirectory(archiveFile);

      final decodedEntries = <ArchiveFile>[];
      archiveInput = InputFileStream(archiveFile.path);
      final archive = ZipDecoder().decodeStream(
        archiveInput,
        callback: decodedEntries.add,
      );
      _validateArchiveHeaders(decodedEntries);
      final uniqueEntries = <String, ArchiveFile>{
        for (final entry in archive) entry.name: entry,
      };
      final manifestEntry = uniqueEntries[manifestPath];
      if (manifestEntry == null) {
        throw const BackupException('备份清单缺失。');
      }
      if (manifestEntry.size > limits.maxManifestBytes) {
        throw const BackupException('备份清单超过大小限制。');
      }
      final manifestBytes = _readEntryLimited(
        manifestEntry,
        limits.maxManifestBytes,
      );
      if (manifestBytes.length != manifestEntry.size) {
        throw const BackupException('备份清单解压大小不符。');
      }
      final decodedManifest = jsonDecode(utf8.decode(manifestBytes));
      if (decodedManifest is! Map<String, dynamic>) {
        throw const BackupException('备份清单格式无效。');
      }
      _validateManifestJsonShape(decodedManifest);
      final manifest = BackupManifestV1.fromJson(decodedManifest);
      _validateManifest(manifest);
      final expectedPaths = <String>{
        manifestPath,
        manifest.database.path,
        ...manifest.media.map((entry) => entry.path),
      };
      if (expectedPaths.length != manifest.media.length + 2) {
        throw const BackupException('备份清单包含重复路径。');
      }
      if (uniqueEntries.keys.toSet().difference(expectedPaths).isNotEmpty ||
          expectedPaths.difference(uniqueEntries.keys.toSet()).isNotEmpty) {
        throw const BackupException('备份文件集合与清单不一致。');
      }

      temporary = Directory(
        p.join(inspectionRoot.path, 'baby-growth-inspection-${_safeId()}'),
      );
      await _createUniqueDirectory(temporary);
      for (final entry in uniqueEntries.values) {
        final destination = File(
          p.joinAll([temporary.path, ...entry.name.split('/')]),
        );
        await destination.parent.create(recursive: true);
        final output = _LimitedFileOutput(
          destination.path,
          maxBytes: limits.maxEntryBytes,
        );
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
        if (output.length != entry.size) {
          throw BackupException('文件解压大小不符：${entry.name}');
        }
      }
      await _validateExtracted(temporary, manifest, checkDatabase: true);
      final canonical = await temporary.resolveSymbolicLinks();
      final inspection = BackupInspection(
        temporaryDirectory: canonical,
        manifest: manifest,
      );
      _bindings[inspection] = _InspectionBinding(
        temporaryDirectory: p.normalize(p.absolute(canonical)),
        archiveDirectory: p.normalize(
          p.absolute(await archiveSnapshotDirectory.resolveSymbolicLinks()),
        ),
        archivePath: p.normalize(
          p.absolute(await archiveFile.resolveSymbolicLinks()),
        ),
        archiveSize: archiveSnapshot.size,
        archiveSha256: archiveSnapshot.sha256,
        manifest: manifest,
        manifestSha256: sha256.convert(manifestBytes).toString(),
      );
      return inspection;
    } catch (error) {
      if (temporary != null) await _deleteDirectoryIfPresent(temporary);
      if (archiveSnapshotDirectory != null) {
        await _deleteDirectoryIfPresent(archiveSnapshotDirectory);
      }
      if (error is BackupException) rethrow;
      throw BackupException('检查备份失败', error);
    } finally {
      archiveInput?.closeSync();
    }
  }

  @override
  Future<void> restore(BackupInspection inspected) =>
      destructiveOperationGate.run(() => _restore(inspected));

  Future<void> _restore(BackupInspection inspected) async {
    final binding = _bindings[inspected];
    if (binding == null || !identical(binding.manifest, inspected.manifest)) {
      throw const BackupException('备份检查结果无效或不属于当前会话。');
    }
    final temporary = Directory(binding.temporaryDirectory);
    final supportRoot = await _validatedDirectory(
      await _applicationSupportDirectory(),
      create: true,
      label: '应用数据目录',
    );
    final rollbackRoot = (await _childDirectory(
      supportRoot,
      'backup-rollbacks',
      create: true,
    ))!;
    final state = _RestoreState(
      inspectionDirectory: temporary,
      rollbackDirectory: Directory(
        p.join(rollbackRoot.path, 'rollback-${_safeId()}'),
      ),
      currentMediaPath: p.join(supportRoot.path, 'media'),
    );

    try {
      await _validateBoundInspection(inspected, binding);
      await databaseLifecycle.withClosedDatabase<void>((databasePath) async {
        state.currentDatabasePath = databasePath;
        await _validateBoundInspection(inspected, binding);
        await _createUniqueDirectory(state.rollbackDirectory);
        final rollbackDatabase = File(
          p.join(state.rollbackDirectory.path, 'database', 'app.db'),
        );
        await rollbackDatabase.parent.create(recursive: true);
        state.rollbackDatabasePath = rollbackDatabase.path;
        state.rollbackMediaPath = p.join(state.rollbackDirectory.path, 'media');
        state.failedReplacementDatabasePath = p.join(
          state.rollbackDirectory.path,
          'failed-replacement',
          'database',
          'app.db',
        );
        state.failedReplacementMediaPath = p.join(
          state.rollbackDirectory.path,
          'failed-replacement',
          'media',
        );

        try {
          await _step(BackupRestoreStep.beforeCurrentDatabaseMove);
          await _renamePath(databasePath, rollbackDatabase.path);
          state.currentDatabaseMoved = true;
          await _step(BackupRestoreStep.afterCurrentDatabaseMove);

          if (await FileSystemEntity.type(
                state.currentMediaPath,
                followLinks: false,
              ) ==
              FileSystemEntityType.directory) {
            await _renamePath(state.currentMediaPath, state.rollbackMediaPath);
            state.currentMediaMoved = true;
          }
          await _step(BackupRestoreStep.afterCurrentMediaMove);

          final inspectedDatabase = p.joinAll([
            temporary.path,
            ...databaseArchivePath.split('/'),
          ]);
          await _renamePath(inspectedDatabase, databasePath);
          state.replacementDatabaseMoved = true;
          await _step(BackupRestoreStep.afterReplacementDatabaseMove);

          final inspectedMedia = p.join(temporary.path, 'media');
          if (await FileSystemEntity.type(inspectedMedia, followLinks: false) ==
              FileSystemEntityType.directory) {
            await _renamePath(inspectedMedia, state.currentMediaPath);
            state.replacementMediaMoved = true;
          }
          await _step(BackupRestoreStep.afterReplacementMediaMove);
          await _validateInstalledReplacement(
            databasePath,
            supportRoot: supportRoot,
            manifest: inspected.manifest,
          );
          await _migrateAndVerifyDatabase(
            databasePath,
            supportRoot: supportRoot,
            manifest: inspected.manifest,
          );
          await _step(BackupRestoreStep.afterReplacementVerification);
        } catch (error) {
          try {
            await _rollbackWhileClosed(state);
          } catch (rollbackError) {
            throw BackupRollbackException(
              recoveryPath: state.rollbackDirectory.path,
              originalError: error,
              rollbackError: rollbackError,
            );
          }
          if (error is BackupException) rethrow;
          throw BackupException('恢复备份失败', error);
        }
      });

      try {
        await _verifyReadableDatabase(state.currentDatabasePath!);
      } catch (error) {
        try {
          await databaseLifecycle.withClosedDatabase<void>((_) async {
            await _rollbackWhileClosed(state);
          });
        } catch (rollbackError) {
          throw BackupRollbackException(
            recoveryPath: state.rollbackDirectory.path,
            originalError: error,
            rollbackError: rollbackError,
          );
        }
        throw BackupException('恢复后的数据无法读取', error);
      }
      // Commit point: cleanup below must never re-enter rollback.
    } on DatabaseLifecycleReopenException catch (error) {
      Future<void> reopenAndCleanup() async {
        await databaseLifecycle.reopen();
        await _verifyReadableDatabase(state.currentDatabasePath!);
        if (error.operationError is! BackupRollbackException) {
          await _deleteDirectoryBestEffort(state.rollbackDirectory);
        }
        await _deleteDirectoryBestEffort(temporary);
        await _deleteDirectoryBestEffort(Directory(binding.archiveDirectory));
        _bindings.remove(inspected);
      }

      try {
        await reopenAndCleanup();
      } catch (reopenError) {
        throw BackupReopenException(
          recoveryPath: state.rollbackDirectory.path,
          operationError: error.operationError,
          reopenError: reopenError,
          retryReopen: reopenAndCleanup,
        );
      }
      final operationError = error.operationError;
      if (operationError != null) {
        Error.throwWithStackTrace(
          operationError,
          error.operationStackTrace ?? StackTrace.current,
        );
      }
    } on BackupRollbackException {
      rethrow;
    } catch (error) {
      if (state.replacementDatabaseMoved && !state.rolledBack) {
        try {
          await _rollbackWhileClosed(state);
          await databaseLifecycle.reopen();
        } catch (rollbackError) {
          throw BackupRollbackException(
            recoveryPath: state.rollbackDirectory.path,
            originalError: error,
            rollbackError: rollbackError,
          );
        }
      }
      await _deleteDirectoryBestEffort(temporary);
      await _deleteDirectoryBestEffort(Directory(binding.archiveDirectory));
      if (state.rolledBack) {
        await _deleteDirectoryBestEffort(state.rollbackDirectory);
      }
      _bindings.remove(inspected);
      if (error is BackupException) rethrow;
      throw BackupException('恢复备份失败', error);
    }

    _bindings.remove(inspected);
    await _deleteDirectoryBestEffort(state.rollbackDirectory);
    await _deleteDirectoryBestEffort(temporary);
    await _deleteDirectoryBestEffort(Directory(binding.archiveDirectory));
  }

  @override
  Future<void> removeExpiredExports(Duration maxAge) async {
    if (maxAge.isNegative) {
      throw ArgumentError.value(maxAge, 'maxAge', 'must not be negative');
    }
    final supportRoot = await _validatedDirectory(
      await _applicationSupportDirectory(),
      create: true,
      label: '应用数据目录',
    );
    final exports = await _childDirectory(
      supportRoot,
      'backup-exports',
      create: false,
    );
    if (exports == null) return;
    final cutoff = _now().subtract(maxAge);
    await for (final entity in exports.list(followLinks: false)) {
      if (entity is File &&
          (entity.path.endsWith(archiveExtension) ||
              entity.path.endsWith('$archiveExtension.partial')) &&
          (await entity.lastModified()).isBefore(cutoff)) {
        await entity.delete();
      }
    }
  }

  Future<void> _validateBoundInspection(
    BackupInspection inspected,
    _InspectionBinding binding,
  ) async {
    if (p.normalize(p.absolute(inspected.temporaryDirectory)) !=
        binding.temporaryDirectory) {
      throw const BackupException('备份检查目录已被替换。');
    }
    final directory = Directory(binding.temporaryDirectory);
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.directory ||
        p.normalize(p.absolute(await directory.resolveSymbolicLinks())) !=
            binding.temporaryDirectory) {
      throw const BackupException('备份检查目录不安全。');
    }
    await _validateExtracted(directory, binding.manifest, checkDatabase: true);
    final manifestFile = File(p.join(directory.path, manifestPath));
    final manifestDigest = await sha256.bind(manifestFile.openRead()).first;
    if (manifestDigest.toString() != binding.manifestSha256) {
      throw const BackupException('备份清单检查结果已被替换。');
    }
    final archiveDirectory = Directory(binding.archiveDirectory);
    if (await FileSystemEntity.type(
          archiveDirectory.path,
          followLinks: false,
        ) !=
        FileSystemEntityType.directory) {
      throw const BackupException('备份快照目录已被替换。');
    }
    final archiveFile = File(binding.archivePath);
    if (await FileSystemEntity.type(archiveFile.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await archiveFile.length() != binding.archiveSize) {
      throw const BackupException('备份快照已被替换。');
    }
    final archiveDigest = await sha256.bind(archiveFile.openRead()).first;
    if (archiveDigest.toString() != binding.archiveSha256) {
      throw const BackupException('备份快照已被替换。');
    }
  }

  Future<({int size, String sha256})> _copyArchiveSnapshot(
    File source,
    File destination,
  ) async {
    RandomAccessFile? input;
    RandomAccessFile? output;
    var copied = 0;
    try {
      input = await source.open();
      await destination.create(exclusive: true);
      output = await destination.open(mode: FileMode.writeOnly);
      const chunkSize = 64 * 1024;
      while (true) {
        final bytes = await input.read(chunkSize);
        if (bytes.isEmpty) break;
        copied += bytes.length;
        if (copied > limits.maxArchiveBytes) {
          throw const BackupException('备份文件超过大小限制。');
        }
        await output.writeFrom(bytes);
        await onArchiveCopyChunk?.call(copied);
      }
      await output.flush();
    } finally {
      await output?.close();
      await input?.close();
    }
    if (copied <= 0) {
      throw const BackupException('备份文件大小无效。');
    }
    final digest = await sha256.bind(destination.openRead()).first;
    return (size: copied, sha256: digest.toString());
  }

  static Uint8List _readEntryLimited(ArchiveFile entry, int maxBytes) {
    final output = _LimitedMemoryOutput(maxBytes: maxBytes);
    entry.writeContent(output, freeMemory: false);
    return output.bytes;
  }

  Future<void> _preflightZipDirectory(File archiveFile) async {
    const eocdSignature = 0x06054b50;
    const zip64LocatorSignature = 0x07064b50;
    const zip64EocdSignature = 0x06064b50;
    const centralHeaderSignature = 0x02014b50;
    const eocdSize = 22;
    const zip64LocatorSize = 20;
    const zip64EocdSize = 56;
    const centralHeaderSize = 46;
    const maxCommentSize = 0xffff;

    final input = await archiveFile.open();
    try {
      final archiveLength = await input.length();
      final maxTail = eocdSize + maxCommentSize + zip64LocatorSize;
      final tailLength = archiveLength < maxTail ? archiveLength : maxTail;
      final tailOffset = archiveLength - tailLength;
      final tailBytes = await _readFileRange(input, tailOffset, tailLength);
      final tail = ByteData.sublistView(tailBytes);
      var eocdIndex = -1;
      for (var index = tailLength - 4; index >= 0; index -= 1) {
        if (tail.getUint32(index, Endian.little) == eocdSignature) {
          eocdIndex = index;
          break;
        }
      }
      if (eocdIndex < 0 || eocdIndex + eocdSize > tailLength) {
        throw const BackupException('备份 ZIP 目录无效。');
      }
      final commentLength = tail.getUint16(eocdIndex + 20, Endian.little);
      if (eocdIndex + eocdSize + commentLength != tailLength) {
        throw const BackupException('备份 ZIP 目录无效。');
      }

      final eocdOffset = tailOffset + eocdIndex;
      final diskNumber = tail.getUint16(eocdIndex + 4, Endian.little);
      final centralDisk = tail.getUint16(eocdIndex + 6, Endian.little);
      var entriesOnDisk = tail.getUint16(eocdIndex + 8, Endian.little);
      var entryCount = tail.getUint16(eocdIndex + 10, Endian.little);
      var centralSize = tail.getUint32(eocdIndex + 12, Endian.little);
      var centralOffset = tail.getUint32(eocdIndex + 16, Endian.little);
      var centralBoundary = eocdOffset;

      final hasZip64Sentinels =
          entriesOnDisk == 0xffff ||
          entryCount == 0xffff ||
          centralSize == 0xffffffff ||
          centralOffset == 0xffffffff;
      final locatorOffset = eocdOffset - zip64LocatorSize;
      ByteData? zip64Locator;
      if (locatorOffset >= 0) {
        final locatorBytes = await _readFileRange(
          input,
          locatorOffset,
          zip64LocatorSize,
        );
        final candidate = ByteData.sublistView(locatorBytes);
        if (candidate.getUint32(0, Endian.little) == zip64LocatorSignature) {
          zip64Locator = candidate;
        }
      }
      if (hasZip64Sentinels || zip64Locator != null) {
        final locator = zip64Locator;
        if (locator == null) {
          throw const BackupException('备份 ZIP64 目录无效。');
        }
        if (locator.getUint32(4, Endian.little) != 0 ||
            locator.getUint32(16, Endian.little) != 1) {
          throw const BackupException('备份 ZIP64 目录无效。');
        }
        final zip64Offset = locator.getUint64(8, Endian.little);
        if (zip64Offset < 0 || zip64Offset + zip64EocdSize > locatorOffset) {
          throw const BackupException('备份 ZIP64 目录无效。');
        }
        final zip64Bytes = await _readFileRange(
          input,
          zip64Offset,
          zip64EocdSize,
        );
        final zip64 = ByteData.sublistView(zip64Bytes);
        final recordSize = zip64.getUint64(4, Endian.little);
        if (zip64.getUint32(0, Endian.little) != zip64EocdSignature ||
            recordSize < 44 ||
            zip64Offset + 12 + recordSize > locatorOffset) {
          throw const BackupException('备份 ZIP64 目录无效。');
        }
        if (zip64.getUint32(16, Endian.little) != 0 ||
            zip64.getUint32(20, Endian.little) != 0) {
          throw const BackupException('不支持分卷备份。');
        }
        entriesOnDisk = zip64.getUint64(24, Endian.little);
        entryCount = zip64.getUint64(32, Endian.little);
        centralSize = zip64.getUint64(40, Endian.little);
        centralOffset = zip64.getUint64(48, Endian.little);
        centralBoundary = zip64Offset;
      } else if (diskNumber != 0 || centralDisk != 0) {
        throw const BackupException('不支持分卷备份。');
      }

      if (entriesOnDisk != entryCount) {
        throw const BackupException('不支持分卷备份。');
      }
      if (entryCount > limits.maxEntries) {
        throw const BackupException('备份声明的条目数量超过限制。');
      }
      if (centralOffset < 0 ||
          centralSize < 0 ||
          centralOffset + centralSize > centralBoundary) {
        throw const BackupException('备份 ZIP 目录无效。');
      }

      var cursor = centralOffset;
      final centralEnd = centralOffset + centralSize;
      var parsedEntries = 0;
      final centralEntries = <_ZipCentralEntry>[];
      while (cursor < centralEnd) {
        if (centralEnd - cursor < centralHeaderSize) {
          throw const BackupException('备份 ZIP 目录无效。');
        }
        final headerBytes = await _readFileRange(
          input,
          cursor,
          centralHeaderSize,
        );
        final header = ByteData.sublistView(headerBytes);
        if (header.getUint32(0, Endian.little) != centralHeaderSignature) {
          throw const BackupException('备份 ZIP 目录无效。');
        }
        final flags = header.getUint16(8, Endian.little);
        final method = header.getUint16(10, Endian.little);
        _validateZipFlagsAndMethod(flags, method);
        final crc32 = header.getUint32(16, Endian.little);
        final rawCompressed = header.getUint32(20, Endian.little);
        final rawUncompressed = header.getUint32(24, Endian.little);
        final nameLength = header.getUint16(28, Endian.little);
        final extraLength = header.getUint16(30, Endian.little);
        final commentLength = header.getUint16(32, Endian.little);
        final rawDisk = header.getUint16(34, Endian.little);
        final rawLocalOffset = header.getUint32(42, Endian.little);
        final variableSize = nameLength + extraLength + commentLength;
        final variable = await _readFileRange(
          input,
          cursor + centralHeaderSize,
          variableSize,
        );
        final name = Uint8List.sublistView(variable, 0, nameLength);
        if (name.isEmpty) {
          throw const BackupException('备份 ZIP 文件名无效。');
        }
        final extra = Uint8List.sublistView(
          variable,
          nameLength,
          nameLength + extraLength,
        );
        final resolved = _resolveCentralZip64(
          rawUncompressed: rawUncompressed,
          rawCompressed: rawCompressed,
          rawLocalOffset: rawLocalOffset,
          rawDisk: rawDisk,
          extra: extra,
        );
        if (resolved.disk != 0 ||
            (method == 0 && resolved.compressed != resolved.uncompressed)) {
          throw const BackupException('备份 ZIP 条目结构无效。');
        }
        centralEntries.add(
          _ZipCentralEntry(
            name: Uint8List.fromList(name),
            flags: flags,
            method: method,
            crc32: crc32,
            compressedSize: resolved.compressed,
            uncompressedSize: resolved.uncompressed,
            localOffset: resolved.localOffset,
            zip64Compressed: rawCompressed == 0xffffffff,
            zip64Uncompressed: rawUncompressed == 0xffffffff,
          ),
        );
        cursor += centralHeaderSize + variableSize;
        if (cursor > centralEnd) {
          throw const BackupException('备份 ZIP 目录无效。');
        }
        parsedEntries += 1;
        if (parsedEntries > limits.maxEntries) {
          throw const BackupException('备份声明的条目数量超过限制。');
        }
      }
      if (parsedEntries != entryCount) {
        throw const BackupException('备份 ZIP 条目计数不一致。');
      }

      final localRanges = <({int start, int end})>[];
      for (final entry in centralEntries) {
        if (entry.localOffset < 0 || entry.localOffset + 30 > centralOffset) {
          throw const BackupException('备份 ZIP 本地条目越界。');
        }
        final localBytes = await _readFileRange(input, entry.localOffset, 30);
        final local = ByteData.sublistView(localBytes);
        if (local.getUint32(0, Endian.little) != 0x04034b50) {
          throw const BackupException('备份 ZIP 本地条目无效。');
        }
        final flags = local.getUint16(6, Endian.little);
        final method = local.getUint16(8, Endian.little);
        _validateZipFlagsAndMethod(flags, method);
        final crc32 = local.getUint32(14, Endian.little);
        final rawCompressed = local.getUint32(18, Endian.little);
        final rawUncompressed = local.getUint32(22, Endian.little);
        final nameLength = local.getUint16(26, Endian.little);
        final extraLength = local.getUint16(28, Endian.little);
        final variable = await _readFileRange(
          input,
          entry.localOffset + 30,
          nameLength + extraLength,
        );
        final name = Uint8List.sublistView(variable, 0, nameLength);
        final extra = Uint8List.sublistView(variable, nameLength);
        final sizes = _resolveLocalZip64(
          rawUncompressed: rawUncompressed,
          rawCompressed: rawCompressed,
          extra: extra,
        );
        if (flags != entry.flags ||
            method != entry.method ||
            crc32 != entry.crc32 ||
            !_equalBytes(name, entry.name) ||
            sizes.compressed != entry.compressedSize ||
            sizes.uncompressed != entry.uncompressedSize ||
            (rawCompressed == 0xffffffff) != entry.zip64Compressed ||
            (rawUncompressed == 0xffffffff) != entry.zip64Uncompressed) {
          throw const BackupException('备份 ZIP 中央与本地条目不一致。');
        }
        final dataStart = entry.localOffset + 30 + nameLength + extraLength;
        final dataEnd = dataStart + entry.compressedSize;
        if (dataStart < entry.localOffset || dataEnd > centralOffset) {
          throw const BackupException('备份 ZIP 条目数据越界。');
        }
        localRanges.add((start: entry.localOffset, end: dataEnd));
      }
      localRanges.sort((left, right) => left.start.compareTo(right.start));
      for (var index = 1; index < localRanges.length; index += 1) {
        if (localRanges[index].start < localRanges[index - 1].end) {
          throw const BackupException('备份 ZIP 本地条目重叠。');
        }
      }
    } finally {
      await input.close();
    }
  }

  static Future<Uint8List> _readFileRange(
    RandomAccessFile input,
    int offset,
    int length,
  ) async {
    if (offset < 0 || length < 0) {
      throw const BackupException('备份 ZIP 目录无效。');
    }
    await input.setPosition(offset);
    final bytes = await input.read(length);
    if (bytes.length != length) {
      throw const BackupException('备份 ZIP 目录无效。');
    }
    return bytes;
  }

  static void _validateZipFlagsAndMethod(int flags, int method) {
    if ((flags & ~0x0800) != 0) {
      throw const BackupException('备份 ZIP 使用了不支持的标志。');
    }
    if (method != 0 && method != 8) {
      throw const BackupException('备份 ZIP 使用了不支持的压缩方法。');
    }
  }

  static ({int uncompressed, int compressed, int localOffset, int disk})
  _resolveCentralZip64({
    required int rawUncompressed,
    required int rawCompressed,
    required int rawLocalOffset,
    required int rawDisk,
    required Uint8List extra,
  }) {
    final zip64 = _zip64Extra(extra);
    final needsZip64 =
        rawUncompressed == 0xffffffff ||
        rawCompressed == 0xffffffff ||
        rawLocalOffset == 0xffffffff ||
        rawDisk == 0xffff;
    if (!needsZip64) {
      if (zip64 != null) {
        throw const BackupException('备份 ZIP64 扩展字段多余。');
      }
      return (
        uncompressed: rawUncompressed,
        compressed: rawCompressed,
        localOffset: rawLocalOffset,
        disk: rawDisk,
      );
    }
    if (zip64 == null) {
      throw const BackupException('备份 ZIP64 扩展字段缺失。');
    }
    var cursor = 0;
    int read64() {
      if (cursor + 8 > zip64.lengthInBytes) {
        throw const BackupException('备份 ZIP64 扩展字段无效。');
      }
      final value = zip64.getUint64(cursor, Endian.little);
      cursor += 8;
      return value;
    }

    int read32() {
      if (cursor + 4 > zip64.lengthInBytes) {
        throw const BackupException('备份 ZIP64 扩展字段无效。');
      }
      final value = zip64.getUint32(cursor, Endian.little);
      cursor += 4;
      return value;
    }

    final uncompressed = rawUncompressed == 0xffffffff
        ? read64()
        : rawUncompressed;
    final compressed = rawCompressed == 0xffffffff ? read64() : rawCompressed;
    final localOffset = rawLocalOffset == 0xffffffff
        ? read64()
        : rawLocalOffset;
    final disk = rawDisk == 0xffff ? read32() : rawDisk;
    if (cursor != zip64.lengthInBytes) {
      throw const BackupException('备份 ZIP64 扩展字段无效。');
    }
    return (
      uncompressed: uncompressed,
      compressed: compressed,
      localOffset: localOffset,
      disk: disk,
    );
  }

  static ({int uncompressed, int compressed}) _resolveLocalZip64({
    required int rawUncompressed,
    required int rawCompressed,
    required Uint8List extra,
  }) {
    final zip64 = _zip64Extra(extra);
    final needsZip64 =
        rawUncompressed == 0xffffffff || rawCompressed == 0xffffffff;
    if (!needsZip64) {
      if (zip64 != null) {
        throw const BackupException('备份 ZIP64 扩展字段多余。');
      }
      return (uncompressed: rawUncompressed, compressed: rawCompressed);
    }
    if (zip64 == null) {
      throw const BackupException('备份 ZIP64 扩展字段缺失。');
    }
    var cursor = 0;
    int read64() {
      if (cursor + 8 > zip64.lengthInBytes) {
        throw const BackupException('备份 ZIP64 扩展字段无效。');
      }
      final value = zip64.getUint64(cursor, Endian.little);
      cursor += 8;
      return value;
    }

    final uncompressed = rawUncompressed == 0xffffffff
        ? read64()
        : rawUncompressed;
    final compressed = rawCompressed == 0xffffffff ? read64() : rawCompressed;
    if (cursor != zip64.lengthInBytes) {
      throw const BackupException('备份 ZIP64 扩展字段无效。');
    }
    return (uncompressed: uncompressed, compressed: compressed);
  }

  static ByteData? _zip64Extra(Uint8List extra) {
    ByteData? zip64;
    var cursor = 0;
    final data = ByteData.sublistView(extra);
    while (cursor < extra.length) {
      if (cursor + 4 > extra.length) {
        throw const BackupException('备份 ZIP 扩展字段无效。');
      }
      final id = data.getUint16(cursor, Endian.little);
      final length = data.getUint16(cursor + 2, Endian.little);
      cursor += 4;
      if (cursor + length > extra.length) {
        throw const BackupException('备份 ZIP 扩展字段无效。');
      }
      if (id != 1 || zip64 != null) {
        throw const BackupException('备份 ZIP 扩展字段不受支持。');
      }
      zip64 = ByteData.sublistView(extra, cursor, cursor + length);
      cursor += length;
    }
    return zip64;
  }

  static bool _equalBytes(Uint8List left, Uint8List right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  void _validateArchiveHeaders(List<ArchiveFile> entries) {
    if (entries.isEmpty || entries.length > limits.maxEntries) {
      throw const BackupException('备份条目数量无效。');
    }
    final names = <String>{};
    var total = 0;
    for (final entry in entries) {
      _validateArchivePath(entry.name);
      if (!names.add(entry.name)) {
        throw BackupException('备份包含重复条目：${entry.name}');
      }
      if (!entry.isFile || entry.isSymbolicLink) {
        throw BackupException('备份包含不支持的条目：${entry.name}');
      }
      if (entry.size < 0 || entry.size > limits.maxEntryBytes) {
        throw BackupException('备份条目超过大小限制：${entry.name}');
      }
      total += entry.size;
      if (total > limits.maxTotalBytes) {
        throw const BackupException('备份解压总大小超过限制。');
      }
    }
  }

  static void _validateManifestJsonShape(Map<String, dynamic> json) {
    if (json.keys.toSet().difference(const {
          'format',
          'version',
          'createdAt',
          'database',
          'media',
        }).isNotEmpty ||
        !json.keys.toSet().containsAll(const {
          'format',
          'version',
          'createdAt',
          'database',
          'media',
        })) {
      throw const BackupException('备份清单字段无效。');
    }
    if (json['format'] is! String ||
        json['version'] is! int ||
        json['createdAt'] is! String ||
        json['database'] is! Map<String, dynamic> ||
        json['media'] is! List) {
      throw const BackupException('备份清单字段类型无效。');
    }
    _validateEntryJsonShape(json['database']);
    final media = json['media'];
    if (media is! List) throw const BackupException('媒体清单无效。');
    for (final entry in media) {
      _validateEntryJsonShape(entry);
    }
  }

  static void _validateEntryJsonShape(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.keys.toSet().difference(const {
          'path',
          'sha256',
          'size',
        }).isNotEmpty ||
        !value.keys.toSet().containsAll(const {'path', 'sha256', 'size'})) {
      throw const BackupException('文件清单字段无效。');
    }
    if (value['path'] is! String ||
        value['sha256'] is! String ||
        value['size'] is! int) {
      throw const BackupException('文件清单字段类型无效。');
    }
  }

  static void _validateManifest(BackupManifestV1 manifest) {
    if (manifest.format != 'baby-growth-backup' || manifest.version != 1) {
      throw const BackupException('不支持的备份格式或版本。');
    }
    final createdAt = DateTime.tryParse(manifest.createdAt);
    if (createdAt == null || !createdAt.isUtc) {
      throw const BackupException('备份创建时间无效。');
    }
    if (manifest.database.path != databaseArchivePath) {
      throw const BackupException('数据库备份路径无效。');
    }
    for (final entry in [manifest.database, ...manifest.media]) {
      _validateArchivePath(entry.path);
      if (entry.size < 0 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(entry.sha256)) {
        throw BackupException('文件清单值无效：${entry.path}');
      }
    }
    for (final media in manifest.media) {
      if (!media.path.startsWith('media/')) {
        throw BackupException('媒体备份路径无效：${media.path}');
      }
    }
  }

  static void _validateArchivePath(String value) {
    if (value.isEmpty ||
        value.startsWith('/') ||
        value.contains(r'\') ||
        value.contains('\u0000') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(value)) {
      throw BackupException('不安全的备份路径：$value');
    }
    final segments = value.split('/');
    if (segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      throw BackupException('不安全的备份路径：$value');
    }
  }

  Future<void> _validateExtracted(
    Directory directory,
    BackupManifestV1 manifest, {
    required bool checkDatabase,
  }) async {
    final expected = <String, BackupFileEntry>{
      manifest.database.path: manifest.database,
      for (final entry in manifest.media) entry.path: entry,
    };
    final actual = <String>{};
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const BackupException('检查目录包含符号链接。');
      }
      if (type == FileSystemEntityType.file) {
        final relative = p
            .relative(entity.path, from: directory.path)
            .split(p.separator)
            .join('/');
        actual.add(relative);
      } else if (type != FileSystemEntityType.directory) {
        throw const BackupException('检查目录包含不支持的文件类型。');
      }
    }
    final expectedFiles = {...expected.keys, manifestPath};
    if (actual.difference(expectedFiles).isNotEmpty ||
        expectedFiles.difference(actual).isNotEmpty) {
      throw const BackupException('检查目录文件集合已改变。');
    }
    for (final entry in expected.values) {
      final file = File(p.joinAll([directory.path, ...entry.path.split('/')]));
      await _validateFileEntry(file, entry);
    }
    if (checkDatabase) {
      await _verifyDatabaseIntegrity(
        p.joinAll([directory.path, ...databaseArchivePath.split('/')]),
        expectedMediaPaths: manifest.media.map((entry) => entry.path).toSet(),
      );
    }
  }

  Future<void> _validateInstalledReplacement(
    String databasePath, {
    required Directory supportRoot,
    required BackupManifestV1 manifest,
  }) async {
    await _validateFileEntry(File(databasePath), manifest.database);
    for (final entry in manifest.media) {
      await _validateFileEntry(
        File(p.joinAll([supportRoot.path, ...entry.path.split('/')])),
        entry,
      );
    }
    await _verifyDatabaseIntegrity(
      databasePath,
      expectedMediaPaths: manifest.media.map((entry) => entry.path).toSet(),
    );
  }

  static Future<void> _validateFileEntry(
    File file,
    BackupFileEntry entry,
  ) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw BackupException('备份文件缺失：${entry.path}');
    }
    final size = await file.length();
    if (size != entry.size) {
      throw BackupException('备份文件大小不符：${entry.path}');
    }
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() != entry.sha256) {
      throw BackupException('备份文件校验失败：${entry.path}');
    }
  }

  Future<List<String>> _referencedMediaPaths(String databasePath) async {
    Database? database;
    try {
      database = await _databaseFactory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final paths = <String>{};
      for (final row in await database.query(
        'baby',
        columns: ['avatar_path'],
      )) {
        final path = row['avatar_path'] as String?;
        if (path != null && path.isNotEmpty) paths.add(path);
      }
      for (final row in await database.query(
        'attachments',
        columns: ['file_path', 'thumbnail_path'],
      )) {
        paths.add(row['file_path']! as String);
        final thumbnail = row['thumbnail_path'] as String?;
        if (thumbnail != null && thumbnail.isNotEmpty) paths.add(thumbnail);
      }
      return paths.toList()..sort();
    } catch (error) {
      throw BackupException('无法读取数据库媒体索引', error);
    } finally {
      await database?.close();
    }
  }

  Future<({String archivePath, String sourcePath})> _canonicalMediaSource(
    Directory supportRoot,
    String sourcePath,
  ) async {
    final type = await FileSystemEntity.type(sourcePath, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw BackupException('引用的媒体文件缺失或不安全：$sourcePath');
    }
    final support = p.normalize(p.absolute(supportRoot.path));
    final mediaRoot = p.join(support, 'media');
    final resolved = p.normalize(
      p.absolute(await File(sourcePath).resolveSymbolicLinks()),
    );
    if (!p.isWithin(mediaRoot, resolved)) {
      throw BackupException('引用的媒体文件不在私有媒体目录：$sourcePath');
    }
    final relative = p.relative(resolved, from: support);
    final archivePath = relative.split(p.separator).join('/');
    _validateArchivePath(archivePath);
    return (archivePath: archivePath, sourcePath: resolved);
  }

  Future<BackupFileEntry> _entryForFile(
    String sourcePath,
    String archivePath,
  ) async {
    _validateArchivePath(archivePath);
    final file = File(sourcePath);
    final size = await file.length();
    if (size > limits.maxEntryBytes) {
      throw BackupException('文件超过备份大小限制：$archivePath');
    }
    final digest = await sha256.bind(file.openRead()).first;
    return BackupFileEntry(
      path: archivePath,
      sha256: digest.toString(),
      size: size,
    );
  }

  static Future<Set<String>> _databaseMediaArchivePaths(
    DatabaseExecutor database,
  ) async {
    final paths = <String>{};
    for (final row in await database.query('baby', columns: ['avatar_path'])) {
      final stored = row['avatar_path'] as String?;
      if (stored != null && stored.isNotEmpty) {
        paths.add(_archivePathFromStoredMediaPath(stored));
      }
    }
    for (final row in await database.query(
      'attachments',
      columns: ['file_path', 'thumbnail_path'],
    )) {
      paths.add(_archivePathFromStoredMediaPath(row['file_path']! as String));
      final thumbnail = row['thumbnail_path'] as String?;
      if (thumbnail != null && thumbnail.isNotEmpty) {
        paths.add(_archivePathFromStoredMediaPath(thumbnail));
      }
    }
    return paths;
  }

  static String _archivePathFromStoredMediaPath(String storedPath) {
    final segments = storedPath.replaceAll(r'\', '/').split('/');
    final mediaIndex = segments.lastIndexOf('media');
    if (mediaIndex < 0 || mediaIndex >= segments.length - 2) {
      throw BackupException('数据库包含无效媒体路径：$storedPath');
    }
    final archivePath = segments.sublist(mediaIndex).join('/');
    _validateArchivePath(archivePath);
    if (!archivePath.startsWith('media/originals/') &&
        !archivePath.startsWith('media/thumbnails/')) {
      throw BackupException('数据库包含无效媒体路径：$storedPath');
    }
    return archivePath;
  }

  static Future<void> _rebaseMediaPaths(
    Database database, {
    required Directory supportRoot,
    required Set<String> expectedMediaPaths,
  }) => database.transaction((transaction) async {
    final referenced = await _databaseMediaArchivePaths(transaction);
    if (referenced.difference(expectedMediaPaths).isNotEmpty ||
        expectedMediaPaths.difference(referenced).isNotEmpty) {
      throw const BackupException('数据库媒体索引与备份清单不一致。');
    }

    String rebase(String storedPath) {
      final archivePath = _archivePathFromStoredMediaPath(storedPath);
      return p.joinAll([supportRoot.path, ...archivePath.split('/')]);
    }

    for (final row in await transaction.query(
      'baby',
      columns: ['id', 'avatar_path'],
    )) {
      final avatar = row['avatar_path'] as String?;
      if (avatar != null && avatar.isNotEmpty) {
        await transaction.update(
          'baby',
          {'avatar_path': rebase(avatar)},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
    for (final row in await transaction.query(
      'attachments',
      columns: ['id', 'file_path', 'thumbnail_path'],
    )) {
      final thumbnail = row['thumbnail_path'] as String?;
      await transaction.update(
        'attachments',
        {
          'file_path': rebase(row['file_path']! as String),
          'thumbnail_path': thumbnail == null || thumbnail.isEmpty
              ? null
              : rebase(thumbnail),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  });

  Future<void> _verifyDatabaseIntegrity(
    String databasePath, {
    required Set<String> expectedMediaPaths,
  }) async {
    Database? database;
    try {
      database = await _databaseFactory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final integrity = await database.rawQuery('PRAGMA integrity_check');
      if (integrity.length != 1 ||
          integrity.single.values.single.toString().toLowerCase() != 'ok') {
        throw const BackupException('数据库完整性检查失败。');
      }
      final versionRows = await database.rawQuery('PRAGMA user_version');
      final version = versionRows.single.values.single as int;
      if (version > schemaVersion) {
        throw BackupException('数据库版本 $version 高于当前支持版本。');
      }
      final referencedMedia = await _databaseMediaArchivePaths(database);
      if (referencedMedia.difference(expectedMediaPaths).isNotEmpty ||
          expectedMediaPaths.difference(referencedMedia).isNotEmpty) {
        throw const BackupException('数据库媒体索引与备份清单不一致。');
      }
    } catch (error) {
      if (error is BackupException) rethrow;
      throw BackupException('数据库完整性检查失败', error);
    } finally {
      await database?.close();
      await _deleteDatabaseSidecars(databasePath);
    }
  }

  Future<void> _migrateAndVerifyDatabase(
    String databasePath, {
    required Directory supportRoot,
    required BackupManifestV1 manifest,
  }) async {
    Database? database;
    try {
      database = await _databaseFactory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          singleInstance: false,
          onConfigure: (database) async {
            await database.execute('PRAGMA foreign_keys = ON');
            await database.rawQuery('PRAGMA journal_mode = WAL');
          },
          onCreate: (database, version) =>
              migrateDatabase(database, 0, version),
          onUpgrade: migrateDatabase,
        ),
      );
      await _rebaseMediaPaths(
        database,
        supportRoot: supportRoot,
        expectedMediaPaths: manifest.media.map((entry) => entry.path).toSet(),
      );
      await _verifyTables(database);
      for (final entry in manifest.media) {
        final target = p.joinAll([supportRoot.path, ...entry.path.split('/')]);
        if (await FileSystemEntity.type(target, followLinks: false) !=
            FileSystemEntityType.file) {
          throw BackupException('恢复后的媒体文件缺失：${entry.path}');
        }
      }
    } finally {
      await database?.close();
    }
  }

  Future<void> _verifyReadableDatabase(String databasePath) async {
    Database? database;
    try {
      database = await _databaseFactory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      await _verifyTables(database);
    } finally {
      await database?.close();
    }
  }

  static Future<void> _verifyTables(Database database) async {
    await database.query('baby', limit: 1);
    await database.query('records', limit: 1);
  }

  Future<void> _rollbackWhileClosed(_RestoreState state) async {
    if (state.replacementMediaMoved) {
      await Directory(
        state.failedReplacementMediaPath,
      ).parent.create(recursive: true);
      await _renamePath(
        state.currentMediaPath,
        state.failedReplacementMediaPath,
      );
      state.replacementMediaMoved = false;
    }
    if (state.replacementDatabaseMoved) {
      await _deleteDatabaseSidecars(state.currentDatabasePath!);
      await File(
        state.failedReplacementDatabasePath,
      ).parent.create(recursive: true);
      await _renamePath(
        state.currentDatabasePath!,
        state.failedReplacementDatabasePath,
      );
      state.replacementDatabaseMoved = false;
    }

    Object? rollbackFailure;
    if (state.currentDatabaseMoved) {
      await File(state.currentDatabasePath!).parent.create(recursive: true);
      try {
        await _renamePath(
          state.rollbackDatabasePath!,
          state.currentDatabasePath!,
        );
        state.currentDatabaseMoved = false;
      } catch (error) {
        rollbackFailure = error;
        try {
          await _copyRegularFile(
            state.rollbackDatabasePath!,
            state.currentDatabasePath!,
          );
        } catch (_) {
          if (await FileSystemEntity.type(
                state.failedReplacementDatabasePath,
                followLinks: false,
              ) ==
              FileSystemEntityType.file) {
            await _renamePath(
              state.failedReplacementDatabasePath,
              state.currentDatabasePath!,
            );
          }
          rethrow;
        }
      }
    }
    if (state.currentMediaMoved) {
      try {
        await _renamePath(state.rollbackMediaPath, state.currentMediaPath);
        state.currentMediaMoved = false;
      } catch (error) {
        rollbackFailure ??= error;
        if (await FileSystemEntity.type(
              state.failedReplacementMediaPath,
              followLinks: false,
            ) ==
            FileSystemEntityType.directory) {
          await _renamePath(
            state.failedReplacementMediaPath,
            state.currentMediaPath,
          );
        }
      }
    }
    if (rollbackFailure != null) throw rollbackFailure;
    state.rolledBack = true;
  }

  Future<void> _step(BackupRestoreStep step) async {
    await onRestoreStep?.call(step);
  }

  String _safeId() {
    final supplied = _createId();
    final safe = supplied.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return safe.isEmpty ? const Uuid().v4() : safe;
  }

  static Future<Directory> _validatedDirectory(
    Directory directory, {
    required bool create,
    required String label,
  }) async {
    var type = await FileSystemEntity.type(directory.path, followLinks: false);
    if (type == FileSystemEntityType.notFound && create) {
      await directory.create(recursive: true);
      type = await FileSystemEntity.type(directory.path, followLinks: false);
    }
    if (type != FileSystemEntityType.directory) {
      throw BackupException('$label 不存在或不安全。');
    }
    final resolved = p.normalize(
      p.absolute(await directory.resolveSymbolicLinks()),
    );
    return Directory(resolved);
  }

  static Future<Directory?> _childDirectory(
    Directory parent,
    String name, {
    required bool create,
  }) async {
    final child = Directory(p.join(parent.path, name));
    var type = await FileSystemEntity.type(child.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      if (!create) return null;
      await child.create();
      type = await FileSystemEntity.type(child.path, followLinks: false);
    }
    if (type != FileSystemEntityType.directory) {
      throw BackupException('备份工作目录不安全：${child.path}');
    }
    final resolved = p.normalize(
      p.absolute(await child.resolveSymbolicLinks()),
    );
    if (!p.isWithin(parent.path, resolved)) {
      throw BackupException('备份工作目录越界：${child.path}');
    }
    return Directory(resolved);
  }

  static Future<void> _copyRegularFile(
    String source,
    String destination,
  ) async {
    if (await FileSystemEntity.type(source, followLinks: false) !=
        FileSystemEntityType.file) {
      throw BackupException('数据库快照源不安全：$source');
    }
    await File(source).copy(destination);
  }

  static Future<void> _createUniqueDirectory(Directory directory) async {
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw BackupException('备份临时目录冲突：${directory.path}');
    }
    await directory.create();
  }

  static Future<void> _deleteDatabaseSidecars(String databasePath) async {
    for (final path in [
      '$databasePath-wal',
      '$databasePath-shm',
      '$databasePath-journal',
    ]) {
      await _deletePathIfPresent(path);
    }
  }

  static Future<void> _deletePathIfPresent(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.file ||
        type == FileSystemEntityType.link) {
      await File(path).delete();
    } else if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    }
  }

  Future<void> _deleteDirectoryIfPresent(Directory directory) async {
    if (await FileSystemEntity.type(directory.path, followLinks: false) ==
        FileSystemEntityType.directory) {
      await _deleteDirectory(directory);
    }
  }

  Future<void> _deleteDirectoryBestEffort(Directory directory) async {
    try {
      await _deleteDirectoryIfPresent(directory);
    } on FileSystemException {
      // Restore is already committed or rolled back; stale work is safer than
      // re-entering the data swap after a cleanup-only failure.
    }
  }

  static Future<void> _deleteDirectoryRecursively(Directory directory) =>
      directory.delete(recursive: true);

  static Future<void> _rename(String source, String destination) async {
    final type = await FileSystemEntity.type(source, followLinks: false);
    if (type == FileSystemEntityType.file) {
      await File(source).rename(destination);
    } else if (type == FileSystemEntityType.directory) {
      await Directory(source).rename(destination);
    } else {
      throw FileSystemException('Rename source is missing or unsafe', source);
    }
  }

  static Future<void> _share(String archivePath) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(archivePath)], title: '宝宝成长记备份'),
    );
  }
}

class _InspectionBinding {
  const _InspectionBinding({
    required this.temporaryDirectory,
    required this.archiveDirectory,
    required this.archivePath,
    required this.archiveSize,
    required this.archiveSha256,
    required this.manifest,
    required this.manifestSha256,
  });

  final String temporaryDirectory;
  final String archiveDirectory;
  final String archivePath;
  final int archiveSize;
  final String archiveSha256;
  final BackupManifestV1 manifest;
  final String manifestSha256;
}

class _ZipCentralEntry {
  const _ZipCentralEntry({
    required this.name,
    required this.flags,
    required this.method,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localOffset,
    required this.zip64Compressed,
    required this.zip64Uncompressed,
  });

  final Uint8List name;
  final int flags;
  final int method;
  final int crc32;
  final int compressedSize;
  final int uncompressedSize;
  final int localOffset;
  final bool zip64Compressed;
  final bool zip64Uncompressed;
}

class _RestoreState {
  _RestoreState({
    required this.inspectionDirectory,
    required this.rollbackDirectory,
    required this.currentMediaPath,
  });

  final Directory inspectionDirectory;
  final Directory rollbackDirectory;
  final String currentMediaPath;
  String? currentDatabasePath;
  String? rollbackDatabasePath;
  late String rollbackMediaPath;
  late String failedReplacementDatabasePath;
  late String failedReplacementMediaPath;
  bool currentDatabaseMoved = false;
  bool currentMediaMoved = false;
  bool replacementDatabaseMoved = false;
  bool replacementMediaMoved = false;
  bool rolledBack = false;
}

class _LimitedMemoryOutput extends OutputStream {
  _LimitedMemoryOutput({required this.maxBytes})
    : super(byteOrder: ByteOrder.littleEndian);

  final int maxBytes;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  var _length = 0;

  Uint8List get bytes => _builder.takeBytes();

  @override
  int get length => _length;

  void _reserve(int count) {
    if (count < 0 || _length + count > maxBytes) {
      throw const BackupException('备份清单解压后超过大小限制。');
    }
  }

  @override
  void writeByte(int value) {
    _reserve(1);
    _builder.addByte(value);
    _length += 1;
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    _reserve(count);
    _builder.add(count == bytes.length ? bytes : bytes.sublist(0, count));
    _length += count;
  }

  @override
  void writeStream(InputStream stream) {
    var remaining = stream.length;
    const chunkSize = 64 * 1024;
    while (remaining > 0) {
      final count = remaining > chunkSize ? chunkSize : remaining;
      writeBytes(stream.readBytes(count).toUint8List());
      remaining -= count;
    }
  }

  @override
  void clear() {
    _builder.clear();
    _length = 0;
  }

  @override
  void flush() {}

  @override
  Uint8List subset(int start, [int? end]) => bytes.sublist(start, end);
}

class _LimitedFileOutput extends OutputStream {
  _LimitedFileOutput(String path, {required this.maxBytes})
    : _file = File(path).openSync(mode: FileMode.writeOnly),
      super(byteOrder: ByteOrder.littleEndian);

  final RandomAccessFile _file;
  final int maxBytes;
  var _length = 0;
  var _closed = false;

  @override
  int get length => _length;

  void _reserve(int count) {
    if (_closed) throw StateError('Output is closed.');
    if (count < 0 || _length + count > maxBytes) {
      throw const BackupException('备份条目解压后超过大小限制。');
    }
  }

  @override
  void writeByte(int value) {
    _reserve(1);
    _file.writeByteSync(value);
    _length += 1;
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    _reserve(count);
    _file.writeFromSync(bytes, 0, count);
    _length += count;
  }

  @override
  void writeStream(InputStream stream) {
    var remaining = stream.length;
    const chunkSize = 1024 * 1024;
    while (remaining > 0) {
      final count = remaining > chunkSize ? chunkSize : remaining;
      writeBytes(stream.readBytes(count).toUint8List());
      remaining -= count;
    }
  }

  @override
  void flush() => _file.flushSync();

  @override
  void clear() {
    closeSync();
  }

  @override
  void closeSync() {
    if (_closed) return;
    _file.flushSync();
    _file.closeSync();
    _closed = true;
  }

  @override
  Future<void> close() async => closeSync();

  @override
  bool get isOpen => !_closed;

  @override
  Uint8List subset(int start, [int? end]) => Uint8List(0);
}
