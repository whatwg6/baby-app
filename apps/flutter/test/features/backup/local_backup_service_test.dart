import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:baby_growth_timeline/data/database/app_database.dart';
import 'package:baby_growth_timeline/data/database/database_lifecycle.dart';
import 'package:baby_growth_timeline/data/database/migrations.dart';
import 'package:baby_growth_timeline/domain/destructive_operation_gate.dart';
import 'package:baby_growth_timeline/features/backup/data/local_backup_service.dart';
import 'package:baby_growth_timeline/features/backup/domain/backup_manifest.dart';
import 'package:baby_growth_timeline/features/backup/presentation/backup_actions.dart';
import 'package:baby_growth_timeline/features/media/domain/media_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late Directory support;
  late Directory inspections;
  late String databasePath;
  late AppDatabase database;
  late List<String> sharedPaths;
  late int nextId;
  late DestructiveOperationGate destructiveOperationGate;

  String id() => 'id-${nextId++}';

  Future<LocalBackupService> createService({
    DatabaseLifecycle? lifecycle,
    Future<void> Function(String path)? shareArchive,
    BackupArchiveLimits limits = const BackupArchiveLimits(),
    Future<void> Function(BackupRestoreStep step)? onRestoreStep,
    BackupPathRenamer? renamePath,
    BackupDirectoryDeleter? deleteDirectory,
    DateTime Function()? now,
    DestructiveOperationGate? gate,
    BackupArchiveCopyObserver? onArchiveCopyChunk,
  }) async => LocalBackupService(
    databaseLifecycle: lifecycle ?? database,
    destructiveOperationGate: gate ?? destructiveOperationGate,
    databaseFactory: databaseFactoryFfi,
    applicationSupportDirectory: () async => support,
    inspectionDirectory: () async => inspections,
    createId: id,
    now: now ?? () => DateTime.utc(2026, 8, 1, 12),
    shareArchive:
        shareArchive ??
        (path) async {
          sharedPaths.add(path);
        },
    limits: limits,
    onRestoreStep: onRestoreStep,
    renamePath: renamePath,
    deleteDirectory: deleteDirectory,
    onArchiveCopyChunk: onArchiveCopyChunk,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('baby-backup-test-');
    support = Directory(p.join(root.path, 'support'));
    inspections = Directory(p.join(root.path, 'inspections'));
    await support.create(recursive: true);
    databasePath = p.join(support.path, 'app.sqlite');
    database = await AppDatabase.open(
      path: databasePath,
      databaseFactory: databaseFactoryFfi,
    );
    sharedPaths = [];
    nextId = 0;
    destructiveOperationGate = SerialDestructiveOperationGate();
  });

  tearDown(() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'export snapshots a closed database and exactly the referenced media set',
    () async {
      final avatar = await _writeSupportFile(
        support,
        'media/originals/avatar.jpg',
        [1],
      );
      final original = await _writeSupportFile(
        support,
        'media/originals/photo.jpg',
        [2, 3],
      );
      final thumbnail = await _writeSupportFile(
        support,
        'media/thumbnails/photo.jpg',
        [4, 5, 6],
      );
      await _seedDatabase(
        database,
        babyName: '备份宝宝',
        avatarPath: avatar.path,
        originalPath: original.path,
        thumbnailPath: thumbnail.path,
      );
      await _writeSupportFile(support, 'media/originals/orphan.jpg', [99]);
      final observing = _ObservingLifecycle(database);
      final service = await createService(lifecycle: observing);

      final exported = await service.exportBackup();

      expect(observing.sawClosedDatabase, isTrue);
      expect(exported, endsWith('.babygrowth.zip'));
      expect(sharedPaths, [exported]);
      final archive = ZipDecoder().decodeBytes(
        await File(exported).readAsBytes(),
      );
      expect(archive.map((entry) => entry.name).toSet(), {
        'manifest.json',
        'database/app.db',
        'media/originals/avatar.jpg',
        'media/originals/photo.jpg',
        'media/thumbnails/photo.jpg',
      });
      final manifest = BackupManifestV1.fromJson(
        jsonDecode(utf8.decode(archive.findFile('manifest.json')!.content))
            as Map<String, dynamic>,
      );
      expect(manifest.format, 'baby-growth-backup');
      expect(manifest.version, 1);
      expect(manifest.createdAt, '2026-08-01T12:00:00.000Z');
      expect(manifest.database.path, 'database/app.db');
      expect(manifest.media.map((entry) => entry.path).toSet(), {
        'media/originals/avatar.jpg',
        'media/originals/photo.jpg',
        'media/thumbnails/photo.jpg',
      });
      for (final entry in [manifest.database, ...manifest.media]) {
        final bytes = archive.findFile(entry.path)!.content;
        expect(entry.size, bytes.length);
        expect(entry.sha256, sha256.convert(bytes).toString());
      }
    },
  );

  test(
    'export stages referenced media before the closed lifecycle reopens',
    () async {
      final original = await _writeSupportFile(
        support,
        'media/originals/gated.jpg',
        [7, 8, 9],
      );
      await _seedDatabase(
        database,
        babyName: '宝宝',
        originalPath: original.path,
      );
      final lifecycle = _AfterCallbackLifecycle(
        database,
        afterWork: () => original.delete(),
      );
      final service = await createService(lifecycle: lifecycle);

      final exported = await service.exportBackup();

      final archive = ZipDecoder().decodeBytes(
        await File(exported).readAsBytes(),
      );
      expect(archive.findFile('media/originals/gated.jpg')!.content, [7, 8, 9]);
      expect(await original.exists(), isFalse);
    },
  );

  test(
    'export fails before sharing when a referenced media file is missing',
    () async {
      await _seedDatabase(
        database,
        babyName: '宝宝',
        originalPath: p.join(support.path, 'media/originals/missing.jpg'),
      );
      final service = await createService();

      await expectLater(
        service.exportBackup(),
        throwsA(isA<BackupException>()),
      );

      expect(sharedPaths, isEmpty);
    },
  );

  test(
    'export enforces entry, total, and manifest limits before encoding',
    () async {
      final media = await _writeSupportFile(
        support,
        'media/originals/export-limits.jpg',
        [1, 2, 3],
      );
      await _seedDatabase(database, babyName: '宝宝', originalPath: media.path);
      final limits = [
        const BackupArchiveLimits(maxEntries: 2),
        const BackupArchiveLimits(maxTotalBytes: 1),
        const BackupArchiveLimits(maxManifestBytes: 1),
      ];

      for (final configured in limits) {
        final service = await createService(limits: configured);
        await expectLater(
          service.exportBackup(),
          throwsA(isA<BackupException>()),
        );
      }

      expect(sharedPaths, isEmpty);
      final exports = Directory(p.join(support.path, 'backup-exports'));
      expect(
        await exports.exists()
            ? await exports.list(followLinks: false).toList()
            : const <FileSystemEntity>[],
        isEmpty,
      );
    },
  );

  test(
    'a constrained exported archive passes inspection with the same limits',
    () async {
      final media = await _writeSupportFile(
        support,
        'media/originals/export-round-trip.jpg',
        [4, 5, 6],
      );
      await _seedDatabase(database, babyName: '宝宝', originalPath: media.path);
      const configured = BackupArchiveLimits(
        maxArchiveBytes: 2 * 1024 * 1024,
        maxEntryBytes: 1024 * 1024,
        maxTotalBytes: 2 * 1024 * 1024,
        maxEntries: 3,
        maxManifestBytes: 16 * 1024,
      );
      final service = await createService(limits: configured);

      final archive = await service.exportBackup();
      final inspected = await service.inspect(archive);

      expect(
        inspected.manifest.media.single.path,
        endsWith('export-round-trip.jpg'),
      );
    },
  );

  test(
    'share failure retains the completed package and reports its path',
    () async {
      await _seedDatabase(database, babyName: '宝宝');
      final service = await createService(
        shareArchive: (_) async => throw StateError('share unavailable'),
      );

      BackupShareException? error;
      try {
        await service.exportBackup();
      } on BackupShareException catch (caught) {
        error = caught;
      }

      expect(error, isNotNull);
      expect(await File(error!.archivePath).exists(), isTrue);
      expect(error.toString(), contains(error.archivePath));
    },
  );

  test('failed archive rename removes its partial package', () async {
    await _seedDatabase(database, babyName: '宝宝');
    final service = await createService(
      renamePath: (source, destination) async {
        if (source.endsWith('.partial')) {
          throw const FileSystemException('rename failed');
        }
        await _renameEntity(source, destination);
      },
    );

    await expectLater(service.exportBackup(), throwsA(isA<BackupException>()));

    final exports = Directory(p.join(support.path, 'backup-exports'));
    expect(await exports.list(followLinks: false).toList(), isEmpty);
  });

  test(
    'removeExpiredExports deletes only packages older than the max age',
    () async {
      final exports = Directory(p.join(support.path, 'backup-exports'));
      await exports.create(recursive: true);
      final old = await File(
        p.join(exports.path, 'old.babygrowth.zip'),
      ).writeAsBytes([1]);
      final fresh = await File(
        p.join(exports.path, 'fresh.babygrowth.zip'),
      ).writeAsBytes([2]);
      final partial = await File(
        p.join(exports.path, 'stale.babygrowth.zip.partial'),
      ).writeAsBytes([2]);
      final unrelated = await File(
        p.join(exports.path, 'keep.txt'),
      ).writeAsBytes([3]);
      await old.setLastModified(DateTime.utc(2026, 7, 30));
      await fresh.setLastModified(DateTime.utc(2026, 8, 1, 11, 30));
      await partial.setLastModified(DateTime.utc(2026, 7, 30));
      await unrelated.setLastModified(DateTime.utc(2026, 7, 1));
      final service = await createService();

      await service.removeExpiredExports(const Duration(hours: 24));

      expect(await old.exists(), isFalse);
      expect(await fresh.exists(), isTrue);
      expect(await partial.exists(), isFalse);
      expect(await unrelated.exists(), isTrue);
    },
  );

  group('inspect rejects malformed archives', () {
    test('unsupported format and version', () async {
      final service = await createService();
      final wrongFormat = await _createArchiveFixture(
        root,
        databaseFactoryFfi,
        manifestTransform: (json) => {...json, 'format': 'another-format'},
      );
      final wrongVersion = await _createArchiveFixture(
        root,
        databaseFactoryFfi,
        fileName: 'version.babygrowth.zip',
        manifestTransform: (json) => {...json, 'version': 2},
      );

      await expectLater(
        service.inspect(wrongFormat),
        throwsA(isA<BackupException>()),
      );
      await expectLater(
        service.inspect(wrongVersion),
        throwsA(isA<BackupException>()),
      );
    });

    test('null and fractional manifest versions are rejected', () async {
      final service = await createService();
      final nullDefaults = await _createArchiveFixture(
        root,
        databaseFactoryFfi,
        fileName: 'null-version.babygrowth.zip',
        manifestTransform: (json) => {...json, 'format': null, 'version': null},
      );
      final fractional = await _createArchiveFixture(
        root,
        databaseFactoryFfi,
        fileName: 'fractional-version.babygrowth.zip',
        manifestTransform: (json) => {...json, 'version': 1.9},
      );

      await expectLater(
        service.inspect(nullDefaults),
        throwsA(isA<BackupException>()),
      );
      await expectLater(
        service.inspect(fractional),
        throwsA(isA<BackupException>()),
      );
    });

    test('database media references must exactly match the manifest', () async {
      final service = await createService();
      final mismatch = await _createArchiveFixture(
        root,
        databaseFactoryFfi,
        fileName: 'index-mismatch.babygrowth.zip',
        databaseAvatarPath: '/old/media/originals/missing.jpg',
      );

      await expectLater(
        service.inspect(mismatch),
        throwsA(isA<BackupException>()),
      );
    });

    test('missing, extra and duplicate entries', () async {
      final service = await createService();
      final missing = await _createArchiveFixture(
        root,
        databaseFactoryFfi,
        fileName: 'missing.babygrowth.zip',
        omitDatabase: true,
      );
      final extra = await _createArchiveFixture(
        root,
        databaseFactoryFfi,
        fileName: 'extra.babygrowth.zip',
        extraEntries: {
          'extra.txt': [7],
        },
      );
      final duplicate = await _createArchiveFixture(
        root,
        databaseFactoryFfi,
        fileName: 'duplicate.babygrowth.zip',
        duplicateDatabaseEntry: true,
      );

      await expectLater(
        service.inspect(missing),
        throwsA(isA<BackupException>()),
      );
      await expectLater(
        service.inspect(extra),
        throwsA(isA<BackupException>()),
      );
      await expectLater(
        service.inspect(duplicate),
        throwsA(isA<BackupException>()),
      );
    });

    test('manifest size and hash mismatches', () async {
      final service = await createService();
      final wrongSize = await _createArchiveFixture(
        root,
        databaseFactoryFfi,
        fileName: 'size.babygrowth.zip',
        databaseEntryTransform: (entry) => entry.copyWith(size: entry.size + 1),
      );
      final wrongHash = await _createArchiveFixture(
        root,
        databaseFactoryFfi,
        fileName: 'hash.babygrowth.zip',
        databaseEntryTransform: (entry) =>
            entry.copyWith(sha256: List.filled(32, '00').join()),
      );

      await expectLater(
        service.inspect(wrongSize),
        throwsA(isA<BackupException>()),
      );
      await expectLater(
        service.inspect(wrongHash),
        throwsA(isA<BackupException>()),
      );
    });

    test('absolute, backslash, dot-dot and symlink paths', () async {
      final service = await createService();
      final unsafeNames = [
        '/absolute.db',
        r'database\app.db',
        'database/../app.db',
        r'C:/database/app.db',
      ];
      for (var index = 0; index < unsafeNames.length; index += 1) {
        final archive = await _createArchiveFixture(
          root,
          databaseFactoryFfi,
          fileName: 'unsafe-$index.babygrowth.zip',
          unsafeExtraEntry: unsafeNames[index],
        );
        await expectLater(
          service.inspect(archive),
          throwsA(isA<BackupException>()),
        );
      }
      final symlink = await _createArchiveFixture(
        root,
        databaseFactoryFfi,
        fileName: 'symlink.babygrowth.zip',
        includeSymlink: true,
      );
      await expectLater(
        service.inspect(symlink),
        throwsA(isA<BackupException>()),
      );
    });

    test('decompression limits are enforced before extraction', () async {
      final archive = await _createArchiveFixture(root, databaseFactoryFfi);
      final service = await createService(
        limits: const BackupArchiveLimits(
          maxArchiveBytes: 1024 * 1024,
          maxEntryBytes: 8,
          maxTotalBytes: 1024 * 1024,
          maxEntries: 10,
        ),
      );

      await expectLater(
        service.inspect(archive),
        throwsA(isA<BackupException>()),
      );
    });

    test('declared standard and ZIP64 entry counts are preflighted', () async {
      final service = await createService(
        limits: const BackupArchiveLimits(maxEntries: 2),
      );
      final standard = await File(
        p.join(root.path, 'too-many-standard.babygrowth.zip'),
      ).writeAsBytes(_zipEndRecords(declaredEntries: 3), flush: true);
      final zip64 =
          await File(
            p.join(root.path, 'too-many-zip64.babygrowth.zip'),
          ).writeAsBytes(
            _zipEndRecords(declaredEntries: 3, zip64: true),
            flush: true,
          );
      final hiddenZip64 =
          await File(
            p.join(root.path, 'too-many-hidden-zip64.babygrowth.zip'),
          ).writeAsBytes(
            _zipEndRecords(
              declaredEntries: 3,
              zip64: true,
              zip64Sentinels: false,
            ),
            flush: true,
          );
      final excessiveCount = isA<BackupException>().having(
        (error) => error.message,
        'message',
        '备份声明的条目数量超过限制。',
      );

      await expectLater(
        service.inspect(standard.path),
        throwsA(excessiveCount),
      );
      await expectLater(service.inspect(zip64.path), throwsA(excessiveCount));
      await expectLater(
        service.inspect(hiddenZip64.path),
        throwsA(excessiveCount),
      );
    });

    test(
      'preflight rejects the same nearest EOCD chosen by the decoder',
      () async {
        final service = await createService(
          limits: const BackupArchiveLimits(maxEntries: 2),
        );
        final archive = await File(
          p.join(root.path, 'embedded-eocd.babygrowth.zip'),
        ).writeAsBytes(_zipWithEmbeddedEocdSignature(), flush: true);

        await expectLater(
          service.inspect(archive.path),
          throwsA(
            isA<BackupException>().having(
              (error) => error.message,
              'message',
              '备份 ZIP 目录无效。',
            ),
          ),
        );
      },
    );

    test(
      'central and local ZIP metadata must be structurally unambiguous',
      () async {
        final service = await createService();
        final mutations = <String, void Function(Uint8List, int, int)>{
          'local-name': (bytes, central, local) {
            bytes[local + 30] ^= 1;
          },
          'central-crc': (bytes, central, local) {
            final data = ByteData.sublistView(bytes);
            data.setUint32(
              central + 16,
              data.getUint32(central + 16, Endian.little) ^ 1,
              Endian.little,
            );
          },
          'local-crc': (bytes, central, local) {
            final data = ByteData.sublistView(bytes);
            data.setUint32(
              local + 14,
              data.getUint32(local + 14, Endian.little) ^ 1,
              Endian.little,
            );
          },
          'central-encryption': (bytes, central, local) {
            final data = ByteData.sublistView(bytes);
            data.setUint16(
              central + 8,
              data.getUint16(central + 8, Endian.little) | 1,
              Endian.little,
            );
          },
          'local-size': (bytes, central, local) {
            final data = ByteData.sublistView(bytes);
            data.setUint32(
              local + 18,
              data.getUint32(local + 18, Endian.little) + 1,
              Endian.little,
            );
          },
          'descriptor': (bytes, central, local) {
            final data = ByteData.sublistView(bytes);
            data.setUint16(
              central + 8,
              data.getUint16(central + 8, Endian.little) | 0x08,
              Endian.little,
            );
            data.setUint16(
              local + 6,
              data.getUint16(local + 6, Endian.little) | 0x08,
              Endian.little,
            );
          },
          'unsupported-method': (bytes, central, local) {
            final data = ByteData.sublistView(bytes);
            data.setUint16(central + 10, 12, Endian.little);
            data.setUint16(local + 8, 12, Endian.little);
          },
          'missing-zip64-extra': (bytes, central, local) {
            final data = ByteData.sublistView(bytes);
            data.setUint32(central + 24, 0xffffffff, Endian.little);
            data.setUint32(local + 22, 0xffffffff, Endian.little);
          },
          'local-offset-out-of-bounds': (bytes, central, local) {
            ByteData.sublistView(
              bytes,
            ).setUint32(central + 42, central, Endian.little);
          },
          'overlapping-local-ranges': (bytes, central, local) {
            final data = ByteData.sublistView(bytes);
            final nameLength = data.getUint16(central + 28, Endian.little);
            final extraLength = data.getUint16(central + 30, Endian.little);
            final commentLength = data.getUint16(central + 32, Endian.little);
            final secondCentral =
                central + 46 + nameLength + extraLength + commentLength;
            data.setUint32(secondCentral + 42, local, Endian.little);
          },
        };

        for (final mutation in mutations.entries) {
          final archive = await _createMutatedArchive(
            root,
            databaseFactoryFfi,
            mutation.key,
            mutation.value,
          );
          await expectLater(
            service.inspect(archive),
            throwsA(isA<BackupException>()),
            reason: mutation.key,
          );
        }
      },
    );

    test(
      'corrupt SQLite and newer user_version are rejected independently',
      () async {
        final service = await createService();
        final corrupt = await _createArchiveFixture(
          root,
          databaseFactoryFfi,
          fileName: 'corrupt.babygrowth.zip',
          databaseBytes: utf8.encode('not sqlite'),
        );
        final futureDatabase = await _createArchiveFixture(
          root,
          databaseFactoryFfi,
          fileName: 'future.babygrowth.zip',
          databaseUserVersion: schemaVersion + 1,
        );

        await expectLater(
          service.inspect(corrupt),
          throwsA(isA<BackupException>()),
        );
        await expectLater(
          service.inspect(futureDatabase),
          throwsA(isA<BackupException>()),
        );
      },
    );

    test(
      'failed inspections remove their unique temporary directories',
      () async {
        final service = await createService();
        final corrupt = await _createArchiveFixture(
          root,
          databaseFactoryFfi,
          databaseBytes: utf8.encode('broken'),
        );

        await expectLater(
          service.inspect(corrupt),
          throwsA(isA<BackupException>()),
        );

        expect(
          await inspections.exists()
              ? await inspections.list(followLinks: false).toList()
              : const <FileSystemEntity>[],
          isEmpty,
        );
      },
    );
  });

  test(
    'inspect reads a private snapshot when the source path is replaced',
    () async {
      final archive = await _createArchiveFixture(root, databaseFactoryFfi);
      final movedSource = '$archive.original';
      var replaced = false;
      final service = await createService(
        onArchiveCopyChunk: (_) async {
          if (replaced) return;
          replaced = true;
          await File(archive).rename(movedSource);
          await File(archive).writeAsBytes(utf8.encode('replacement'));
        },
      );

      final inspected = await service.inspect(archive);

      expect(replaced, isTrue);
      expect(inspected.manifest.format, 'baby-growth-backup');
      expect(await File(archive).readAsString(), 'replacement');
    },
  );

  test(
    'inspect caps a source archive that grows during snapshot copy',
    () async {
      final archive = await _createArchiveFixture(root, databaseFactoryFfi);
      final initialLength = await File(archive).length();
      var grew = false;
      final service = await createService(
        limits: BackupArchiveLimits(maxArchiveBytes: initialLength + 32),
        onArchiveCopyChunk: (_) async {
          if (grew) return;
          grew = true;
          await File(
            archive,
          ).writeAsBytes(List<int>.filled(1024, 7), mode: FileMode.append);
        },
      );

      await expectLater(
        service.inspect(archive),
        throwsA(
          isA<BackupException>().having(
            (error) => error.message,
            'message',
            '备份文件超过大小限制。',
          ),
        ),
      );

      expect(grew, isTrue);
      expect(
        await inspections.exists()
            ? await inspections.list(followLinks: false).toList()
            : const <FileSystemEntity>[],
        isEmpty,
      );
    },
  );

  test(
    'restore reopens migrated data and removes inspection and rollback data',
    () async {
      await _seedDatabase(database, babyName: '新数据');
      final service = await createService();
      final archive = await service.exportBackup();
      await database.write(
        (db) => db.update(
          'baby',
          {'name': '旧数据'},
          where: 'id = ?',
          whereArgs: ['baby-1'],
        ),
      );
      final inspected = await service.inspect(archive);

      await service.restore(inspected);

      final rows = await database.read((db) => db.query('baby'));
      expect(rows.single['name'], '新数据');
      expect(database.isOpen, isTrue);
      expect(await Directory(inspected.temporaryDirectory).exists(), isFalse);
      final rollbacks = Directory(p.join(support.path, 'backup-rollbacks'));
      expect(
        await rollbacks.exists()
            ? await rollbacks.list(followLinks: false).toList()
            : const <FileSystemEntity>[],
        isEmpty,
      );
    },
  );

  test(
    'restore rebases absolute media indexes to the current support root',
    () async {
      final sourceSupport = await Directory(
        p.join(root.path, 'source-support'),
      ).create(recursive: true);
      final sourceDatabase = await AppDatabase.open(
        path: p.join(sourceSupport.path, 'app.sqlite'),
        databaseFactory: databaseFactoryFfi,
      );
      final sourceAvatar = await _writeSupportFile(
        sourceSupport,
        'media/originals/avatar.jpg',
        [1],
      );
      final sourceOriginal = await _writeSupportFile(
        sourceSupport,
        'media/originals/photo.jpg',
        [2],
      );
      final sourceThumbnail = await _writeSupportFile(
        sourceSupport,
        'media/thumbnails/photo.jpg',
        [3],
      );
      await _seedDatabase(
        sourceDatabase,
        babyName: '迁移宝宝',
        avatarPath: sourceAvatar.path,
        originalPath: sourceOriginal.path,
        thumbnailPath: sourceThumbnail.path,
      );
      final sourceService = LocalBackupService(
        databaseLifecycle: sourceDatabase,
        destructiveOperationGate: destructiveOperationGate,
        databaseFactory: databaseFactoryFfi,
        applicationSupportDirectory: () async => sourceSupport,
        inspectionDirectory: () async => inspections,
        createId: id,
        now: () => DateTime.utc(2026, 8, 1, 12),
        shareArchive: (_) async {},
      );
      final archive = await sourceService.exportBackup();
      await sourceDatabase.close();
      await _seedDatabase(database, babyName: '当前宝宝');
      final targetService = await createService();
      final inspected = await targetService.inspect(archive);

      await targetService.restore(inspected);

      final babyRows = await database.read((db) => db.query('baby'));
      final attachmentRows = await database.read(
        (db) => db.query('attachments'),
      );
      final canonicalSupport = await support.resolveSymbolicLinks();
      expect(
        babyRows.single['avatar_path'],
        p.join(canonicalSupport, 'media', 'originals', 'avatar.jpg'),
      );
      expect(
        attachmentRows.single['file_path'],
        p.join(canonicalSupport, 'media', 'originals', 'photo.jpg'),
      );
      expect(
        attachmentRows.single['thumbnail_path'],
        p.join(canonicalSupport, 'media', 'thumbnails', 'photo.jpg'),
      );
      expect(
        await File(babyRows.single['avatar_path']! as String).readAsBytes(),
        [1],
      );
      expect(
        await File(attachmentRows.single['file_path']! as String).readAsBytes(),
        [2],
      );
    },
  );

  test(
    'post-commit inspection cleanup failure never rolls back restored data',
    () async {
      await _seedDatabase(database, babyName: '新数据');
      final exporter = await createService();
      final archive = await exporter.exportBackup();
      await database.write(
        (db) => db.update(
          'baby',
          {'name': '旧数据'},
          where: 'id = ?',
          whereArgs: ['baby-1'],
        ),
      );
      final restorer = await createService(
        deleteDirectory: (directory) async {
          if (directory.path.contains('baby-growth-inspection-')) {
            throw const FileSystemException('inspection cleanup failed');
          }
          await directory.delete(recursive: true);
        },
      );
      final inspected = await restorer.inspect(archive);

      await restorer.restore(inspected);

      final rows = await database.read((db) => db.query('baby'));
      expect(rows.single['name'], '新数据');
      expect(database.isOpen, isTrue);
    },
  );

  test(
    'restore revalidates and binds inspected artifacts before swapping',
    () async {
      await _seedDatabase(database, babyName: '新数据');
      final service = await createService();
      final archive = await service.exportBackup();
      await database.write(
        (db) => db.update(
          'baby',
          {'name': '旧数据'},
          where: 'id = ?',
          whereArgs: ['baby-1'],
        ),
      );
      final inspected = await service.inspect(archive);
      await File(
        p.join(inspected.temporaryDirectory, 'database', 'app.db'),
      ).writeAsBytes(utf8.encode('swapped'));

      await expectLater(
        service.restore(inspected),
        throwsA(isA<BackupException>()),
      );

      final rows = await database.read((db) => db.query('baby'));
      expect(rows.single['name'], '旧数据');
    },
  );

  test(
    'restore revalidates media after final validation and installation',
    () async {
      final media = await _writeSupportFile(
        support,
        'media/originals/installed-revalidation.jpg',
        [1],
      );
      await _seedDatabase(database, babyName: '新数据', originalPath: media.path);
      final exporter = await createService();
      final archive = await exporter.exportBackup();
      await media.writeAsBytes([9], flush: true);
      await database.write(
        (db) => db.update(
          'baby',
          {'name': '旧数据'},
          where: 'id = ?',
          whereArgs: ['baby-1'],
        ),
      );
      late String inspectionPath;
      final restorer = await createService(
        onRestoreStep: (step) async {
          if (step == BackupRestoreStep.beforeCurrentDatabaseMove) {
            await File(
              p.join(
                inspectionPath,
                'media',
                'originals',
                'installed-revalidation.jpg',
              ),
            ).writeAsBytes([2], flush: true);
          }
        },
      );
      final inspected = await restorer.inspect(archive);
      inspectionPath = inspected.temporaryDirectory;

      await expectLater(
        restorer.restore(inspected),
        throwsA(isA<BackupException>()),
      );

      expect(
        (await database.read((db) => db.query('baby'))).single['name'],
        '旧数据',
      );
      expect(await media.readAsBytes(), [9]);
    },
  );

  test('restore rejects a valid database substituted during rename', () async {
    final media = await _writeSupportFile(
      support,
      'media/originals/database-substitution.jpg',
      [1],
    );
    await _seedDatabase(database, babyName: '备份数据', originalPath: media.path);
    final exporter = await createService();
    final archive = await exporter.exportBackup();
    await media.writeAsBytes([9], flush: true);
    await database.write(
      (db) => db.update(
        'baby',
        {'name': '当前数据'},
        where: 'id = ?',
        whereArgs: ['baby-1'],
      ),
    );
    final substitutePath = p.join(root.path, 'substitute.sqlite');
    final substitute = await AppDatabase.open(
      path: substitutePath,
      databaseFactory: databaseFactoryFfi,
    );
    await _seedDatabase(substitute, babyName: '替换数据', originalPath: media.path);
    await substitute.close();
    final restorer = await createService(
      renamePath: (source, destination) async {
        await _renameEntity(source, destination);
        if (source.contains('baby-growth-inspection-') &&
            destination == databasePath) {
          await File(substitutePath).copy(destination);
        }
      },
    );
    final inspected = await restorer.inspect(archive);

    await expectLater(
      restorer.restore(inspected),
      throwsA(isA<BackupException>()),
    );

    expect(
      (await database.read((db) => db.query('baby'))).single['name'],
      '当前数据',
    );
    expect(await media.readAsBytes(), [9]);
  });

  test('every injected swap failure restores readable old data', () async {
    const steps = [
      BackupRestoreStep.beforeCurrentDatabaseMove,
      BackupRestoreStep.afterCurrentDatabaseMove,
      BackupRestoreStep.afterCurrentMediaMove,
      BackupRestoreStep.afterReplacementDatabaseMove,
      BackupRestoreStep.afterReplacementMediaMove,
      BackupRestoreStep.afterReplacementVerification,
    ];
    for (final failingStep in steps) {
      await database.close();
      await databaseFactoryFfi.deleteDatabase(databasePath);
      database = await AppDatabase.open(
        path: databasePath,
        databaseFactory: databaseFactoryFfi,
      );
      final media = await _writeSupportFile(
        support,
        'media/originals/failure-matrix.jpg',
        [1],
      );
      await _seedDatabase(database, babyName: '新数据', originalPath: media.path);
      final exporter = await createService();
      final archive = await exporter.exportBackup();
      await media.writeAsBytes([9], flush: true);
      await database.write(
        (db) => db.update(
          'baby',
          {'name': '旧数据'},
          where: 'id = ?',
          whereArgs: ['baby-1'],
        ),
      );
      final restorer = await createService(
        onRestoreStep: (step) async {
          if (step == failingStep) throw StateError('injected $step');
        },
      );
      final inspected = await restorer.inspect(archive);

      await expectLater(restorer.restore(inspected), throwsA(anything));

      final rows = await database.read((db) => db.query('baby'));
      expect(rows.single['name'], '旧数据', reason: '$failingStep');
      expect(database.isOpen, isTrue, reason: '$failingStep');
      expect(await media.readAsBytes(), [9], reason: '$failingStep');
    }
  });

  test(
    'rollback failure preserves and reports the manual recovery path',
    () async {
      await _seedDatabase(database, babyName: '新数据');
      final exporter = await createService();
      final archive = await exporter.exportBackup();
      await database.write(
        (db) => db.update(
          'baby',
          {'name': '旧数据'},
          where: 'id = ?',
          whereArgs: ['baby-1'],
        ),
      );
      final restorer = await createService(
        onRestoreStep: (step) async {
          if (step == BackupRestoreStep.afterReplacementDatabaseMove) {
            throw StateError('install failed');
          }
        },
        renamePath: (source, destination) async {
          if (source.contains('backup-rollbacks') &&
              destination == databasePath) {
            throw const FileSystemException('rollback rename failed');
          }
          await _renameEntity(source, destination);
        },
      );
      final inspected = await restorer.inspect(archive);

      BackupRollbackException? error;
      try {
        await restorer.restore(inspected);
      } on BackupRollbackException catch (caught) {
        error = caught;
      }

      expect(error, isNotNull);
      expect(await Directory(error!.recoveryPath).exists(), isTrue);
      expect(error.toString(), contains(error.recoveryPath));
      expect(database.isOpen, isTrue);
      final rows = await database.read((db) => db.query('baby'));
      expect(rows.single['name'], '旧数据');
    },
  );

  test(
    'callback and reopen failures preserve recovery until retry succeeds',
    () async {
      await _seedDatabase(database, babyName: '备份数据');
      final exporter = await createService();
      final archive = await exporter.exportBackup();
      await database.write(
        (db) => db.update(
          'baby',
          {'name': '当前数据'},
          where: 'id = ?',
          whereArgs: ['baby-1'],
        ),
      );
      final failingLifecycle = _ReopenFailureLifecycle(
        database,
        explicitFailures: 1,
      );
      final restorer = await createService(
        lifecycle: failingLifecycle,
        onRestoreStep: (step) async {
          if (step == BackupRestoreStep.afterReplacementDatabaseMove) {
            throw StateError('install callback failed');
          }
        },
      );
      final inspected = await restorer.inspect(archive);

      BackupReopenException? failure;
      try {
        await restorer.restore(inspected);
      } on BackupReopenException catch (error) {
        failure = error;
      }

      expect(failure, isNotNull);
      expect(failure!.operationError, isA<BackupException>());
      expect(await Directory(failure.recoveryPath).exists(), isTrue);
      expect(await Directory(inspected.temporaryDirectory).exists(), isTrue);
      expect(database.isOpen, isFalse);

      await failure.retryReopen();

      expect(database.isOpen, isTrue);
      expect(
        (await database.read((db) => db.query('baby'))).single['name'],
        '当前数据',
      );
      expect(await Directory(failure.recoveryPath).exists(), isFalse);
      expect(await Directory(inspected.temporaryDirectory).exists(), isFalse);
    },
  );

  test(
    'clearAllData commits indexes before cleanup and queues failures',
    () async {
      final media = await _writeSupportFile(
        support,
        'media/originals/clear.jpg',
        [1, 2],
      );
      await _seedDatabase(
        database,
        babyName: '宝宝',
        avatarPath: media.path,
        originalPath: media.path,
      );
      final events = <String>[];
      final queued = <String>{};
      final mediaService = _ClearMediaService(events);

      await clearAllData(
        database: database,
        mediaService: mediaService,
        destructiveOperationGate: destructiveOperationGate,
        queueOrphanCleanup: (paths) async {
          final babyRows = await database.read((db) => db.query('baby'));
          final recordRows = await database.read((db) => db.query('records'));
          expect(babyRows, isEmpty);
          expect(recordRows, isEmpty);
          events.add('queued');
          queued.addAll(paths);
        },
      );

      expect(events, ['remove', 'queued']);
      expect(queued, {media.path});
    },
  );

  test(
    'clearAllData reports a committed cleanup failure with retry paths',
    () async {
      final media = await _writeSupportFile(
        support,
        'media/originals/clear-queue-failure.jpg',
        [4, 5],
      );
      await _seedDatabase(database, babyName: '宝宝', avatarPath: media.path);

      ClearAllDataCleanupException? failure;
      try {
        await clearAllData(
          database: database,
          mediaService: _ClearMediaService(<String>[]),
          destructiveOperationGate: destructiveOperationGate,
          queueOrphanCleanup: (_) async {
            throw StateError('queue unavailable');
          },
        );
      } on ClearAllDataCleanupException catch (error) {
        failure = error;
      }

      expect(failure, isNotNull);
      expect(failure!.paths, {media.path});
      expect(failure.toString(), '数据已清空，但媒体清理排队失败');
      expect(await database.read((db) => db.query('baby')), isEmpty);
      expect(await database.read((db) => db.query('records')), isEmpty);
    },
  );

  test(
    'paused clear cleanup completes before restore installs replacement media',
    () async {
      final media = await _writeSupportFile(
        support,
        'media/originals/serialized.jpg',
        [1],
      );
      await _seedDatabase(database, babyName: '备份宝宝', originalPath: media.path);
      final exporter = await createService();
      final archive = await exporter.exportBackup();
      await media.writeAsBytes([9], flush: true);
      final restorer = await createService();
      final inspected = await restorer.inspect(archive);
      final cleanup = _PausingRemoveMediaService();

      final clear = clearAllData(
        database: database,
        mediaService: cleanup,
        destructiveOperationGate: destructiveOperationGate,
        queueOrphanCleanup: (_) async {},
      );
      await cleanup.started.future;
      var restoreCompleted = false;
      final restore = restorer.restore(inspected).then((_) {
        restoreCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);

      expect(restoreCompleted, isFalse);
      expect(await media.readAsBytes(), [9]);

      cleanup.release.complete();
      await clear;
      await restore;

      expect(await media.readAsBytes(), [1]);
      final babies = await database.read((db) => db.query('baby'));
      expect(babies.single['name'], '备份宝宝');
    },
  );
}

class _ObservingLifecycle implements DatabaseLifecycle {
  _ObservingLifecycle(this.database);

  final AppDatabase database;
  bool sawClosedDatabase = false;

  @override
  Future<void> reopen() => database.reopen();

  @override
  Future<T> withClosedDatabase<T>(
    Future<T> Function(String databasePath) work,
  ) => database.withClosedDatabase((path) {
    sawClosedDatabase = !database.isOpen;
    return work(path);
  });
}

class _AfterCallbackLifecycle implements DatabaseLifecycle {
  _AfterCallbackLifecycle(this.database, {required this.afterWork});

  final AppDatabase database;
  final Future<void> Function() afterWork;

  @override
  Future<void> reopen() => database.reopen();

  @override
  Future<T> withClosedDatabase<T>(
    Future<T> Function(String databasePath) work,
  ) => database.withClosedDatabase((path) async {
    final result = await work(path);
    await afterWork();
    return result;
  });
}

class _ReopenFailureLifecycle implements DatabaseLifecycle {
  _ReopenFailureLifecycle(this.database, {required this.explicitFailures});

  final AppDatabase database;
  int explicitFailures;

  @override
  Future<T> withClosedDatabase<T>(
    Future<T> Function(String databasePath) work,
  ) async {
    Object? operationError;
    StackTrace? operationStackTrace;
    try {
      await database.withClosedDatabase(work);
    } catch (error, stackTrace) {
      operationError = error;
      operationStackTrace = stackTrace;
    }
    await database.close();
    throw DatabaseLifecycleReopenException(
      operationError: operationError,
      operationStackTrace: operationStackTrace,
      reopenError: StateError('automatic reopen failed'),
      reopenStackTrace: StackTrace.current,
    );
  }

  @override
  Future<void> reopen() async {
    if (explicitFailures > 0) {
      explicitFailures -= 1;
      throw StateError('explicit reopen failed');
    }
    await database.reopen();
  }
}

class _ClearMediaService implements MediaService {
  _ClearMediaService(this.events);

  final List<String> events;

  @override
  Future<void> remove(Iterable<String> paths) async {
    events.add('remove');
    throw StateError('cleanup failed');
  }

  @override
  Future<CommittedMedia> commit(StagedMedia staged) =>
      throw UnimplementedError();

  @override
  Future<void> removeOrphans(Set<String> referencedPaths) =>
      throw UnimplementedError();

  @override
  Future<void> rollback(StagedMedia staged) => throw UnimplementedError();

  @override
  Future<StagedMedia> stage(PickedMedia input) => throw UnimplementedError();
}

class _PausingRemoveMediaService implements MediaService {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> remove(Iterable<String> paths) async {
    started.complete();
    await release.future;
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<CommittedMedia> commit(StagedMedia staged) =>
      throw UnimplementedError();

  @override
  Future<void> removeOrphans(Set<String> referencedPaths) =>
      throw UnimplementedError();

  @override
  Future<void> rollback(StagedMedia staged) => throw UnimplementedError();

  @override
  Future<StagedMedia> stage(PickedMedia input) => throw UnimplementedError();
}

Future<File> _writeSupportFile(
  Directory support,
  String relativePath,
  List<int> bytes,
) async {
  final file = File(p.joinAll([support.path, ...relativePath.split('/')]));
  await file.parent.create(recursive: true);
  return file.writeAsBytes(bytes, flush: true);
}

Future<void> _seedDatabase(
  AppDatabase database, {
  required String babyName,
  String? avatarPath,
  String? originalPath,
  String? thumbnailPath,
}) => database.transaction((db) async {
  await db.delete('baby');
  await db.delete('records');
  await db.insert('baby', {
    'id': 'baby-1',
    'name': babyName,
    'birth_date': '2025-06-15',
    'avatar_path': avatarPath,
    'created_at': '2026-08-01T00:00:00.000Z',
    'updated_at': '2026-08-01T00:00:00.000Z',
  });
  if (originalPath != null) {
    await db.insert('records', {
      'id': 'record-1',
      'type': 'moment',
      'occurred_at': '2026-08-01T00:00:00.000Z',
      'created_at': '2026-08-01T00:00:00.000Z',
      'updated_at': '2026-08-01T00:00:00.000Z',
    });
    await db.insert('attachments', {
      'id': 'attachment-1',
      'record_id': 'record-1',
      'media_type': 'image',
      'file_path': originalPath,
      'thumbnail_path': thumbnailPath,
      'created_at': '2026-08-01T00:00:00.000Z',
    });
  }
});

Future<String> _createArchiveFixture(
  Directory root,
  DatabaseFactory factory, {
  String fileName = 'fixture.babygrowth.zip',
  Map<String, dynamic> Function(Map<String, dynamic>)? manifestTransform,
  BackupFileEntry Function(BackupFileEntry)? databaseEntryTransform,
  bool omitDatabase = false,
  Map<String, List<int>> extraEntries = const {},
  String? unsafeExtraEntry,
  bool includeSymlink = false,
  bool duplicateDatabaseEntry = false,
  List<int>? databaseBytes,
  int databaseUserVersion = schemaVersion,
  String? databaseAvatarPath,
}) async {
  final fixtureDirectory = await Directory(
    p.join(root.path, 'fixture-${DateTime.now().microsecondsSinceEpoch}'),
  ).create(recursive: true);
  final fixtureDatabase = p.join(fixtureDirectory.path, 'app.db');
  if (databaseBytes == null) {
    final db = await factory.openDatabase(
      fixtureDatabase,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        singleInstance: false,
        onCreate: (database, version) => migrateDatabase(database, 0, version),
      ),
    );
    await db.insert('baby', {
      'id': 'backup-baby',
      'name': '备份宝宝',
      'birth_date': '2025-06-15',
      'avatar_path': databaseAvatarPath,
      'created_at': '2026-08-01T00:00:00.000Z',
      'updated_at': '2026-08-01T00:00:00.000Z',
    });
    await db.execute('PRAGMA user_version = $databaseUserVersion');
    await db.close();
    databaseBytes = await File(fixtureDatabase).readAsBytes();
  }
  var databaseEntry = BackupFileEntry(
    path: 'database/app.db',
    sha256: sha256.convert(databaseBytes).toString(),
    size: databaseBytes.length,
  );
  databaseEntry = databaseEntryTransform?.call(databaseEntry) ?? databaseEntry;
  final manifest = BackupManifestV1(
    createdAt: '2026-08-01T12:00:00.000Z',
    database: databaseEntry,
    media: const [],
  );
  var manifestJson = manifest.toJson();
  manifestJson = manifestTransform?.call(manifestJson) ?? manifestJson;
  final archive = Archive()
    ..addFile(ArchiveFile.string('manifest.json', jsonEncode(manifestJson)));
  if (!omitDatabase) {
    archive.addFile(ArchiveFile.bytes('database/app.db', databaseBytes));
  }
  for (final entry in extraEntries.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  if (unsafeExtraEntry != null) {
    archive.addFile(ArchiveFile.bytes(unsafeExtraEntry, [9]));
  }
  if (includeSymlink) {
    final link = ArchiveFile.string('media/link.jpg', '../../outside')
      ..mode = 0xA1FF;
    archive.addFile(link);
  }
  final output = OutputMemoryStream();
  final encoder = ZipEncoder()..startEncode(output);
  for (final entry in archive) {
    encoder.add(entry, autoClose: false);
    if (duplicateDatabaseEntry && entry.name == 'database/app.db') {
      encoder.add(
        ArchiveFile.bytes('database/app.db', databaseBytes),
        autoClose: false,
      );
    }
  }
  encoder.endEncode();
  final archivePath = p.join(root.path, fileName);
  await File(archivePath).writeAsBytes(output.getBytes(), flush: true);
  return archivePath;
}

Future<void> _renameEntity(String source, String destination) async {
  final type = await FileSystemEntity.type(source, followLinks: false);
  if (type == FileSystemEntityType.file) {
    await File(source).rename(destination);
  } else if (type == FileSystemEntityType.directory) {
    await Directory(source).rename(destination);
  } else {
    throw FileSystemException('Missing rename source', source);
  }
}

Future<String> _createMutatedArchive(
  Directory root,
  DatabaseFactory factory,
  String name,
  void Function(Uint8List bytes, int centralOffset, int localOffset) mutate,
) async {
  final archive = await _createArchiveFixture(
    root,
    factory,
    fileName: '$name.babygrowth.zip',
  );
  final bytes = await File(archive).readAsBytes();
  final data = ByteData.sublistView(bytes);
  var eocd = -1;
  for (var offset = bytes.length - 4; offset >= 0; offset -= 1) {
    if (data.getUint32(offset, Endian.little) == 0x06054b50) {
      eocd = offset;
      break;
    }
  }
  if (eocd < 0) throw StateError('fixture EOCD missing');
  final central = data.getUint32(eocd + 16, Endian.little);
  final local = data.getUint32(central + 42, Endian.little);
  mutate(bytes, central, local);
  await File(archive).writeAsBytes(bytes, flush: true);
  return archive;
}

Uint8List _zipEndRecords({
  required int declaredEntries,
  bool zip64 = false,
  bool zip64Sentinels = true,
}) {
  if (!zip64) {
    final bytes = Uint8List(22);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, 0x06054b50, Endian.little);
    data.setUint16(8, declaredEntries, Endian.little);
    data.setUint16(10, declaredEntries, Endian.little);
    return bytes;
  }

  final bytes = Uint8List(98);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 0x06064b50, Endian.little);
  data.setUint64(4, 44, Endian.little);
  data.setUint16(12, 45, Endian.little);
  data.setUint16(14, 45, Endian.little);
  data.setUint64(24, declaredEntries, Endian.little);
  data.setUint64(32, declaredEntries, Endian.little);

  data.setUint32(56, 0x07064b50, Endian.little);
  data.setUint64(64, 0, Endian.little);
  data.setUint32(72, 1, Endian.little);

  data.setUint32(76, 0x06054b50, Endian.little);
  if (zip64Sentinels) {
    data.setUint16(84, 0xffff, Endian.little);
    data.setUint16(86, 0xffff, Endian.little);
    data.setUint32(88, 0xffffffff, Endian.little);
    data.setUint32(92, 0xffffffff, Endian.little);
  }
  return bytes;
}

Uint8List _zipWithEmbeddedEocdSignature() {
  final bytes = Uint8List(52);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 0x06054b50, Endian.little);
  data.setUint16(20, 30, Endian.little);

  data.setUint32(24, 0x06054b50, Endian.little);
  data.setUint16(32, 3, Endian.little);
  data.setUint16(34, 3, Endian.little);
  return bytes;
}
