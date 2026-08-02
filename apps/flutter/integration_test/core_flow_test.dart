import 'dart:io';

import 'package:baby_growth_timeline/data/database/app_database.dart';
import 'package:baby_growth_timeline/data/repositories/sqlite_baby_repository.dart';
import 'package:baby_growth_timeline/data/repositories/sqlite_record_repository.dart';
import 'package:baby_growth_timeline/domain/date/timeline_grouping.dart';
import 'package:baby_growth_timeline/domain/destructive_operation_gate.dart';
import 'package:baby_growth_timeline/domain/models/attachment.dart';
import 'package:baby_growth_timeline/domain/models/baby.dart';
import 'package:baby_growth_timeline/domain/models/record_draft.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';
import 'package:baby_growth_timeline/features/backup/data/local_backup_service.dart';
import 'package:baby_growth_timeline/features/backup/presentation/backup_actions.dart';
import 'package:baby_growth_timeline/features/media/data/local_media_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline core flow survives restart, backup, and restore', (
    tester,
  ) async {
    final base = await getTemporaryDirectory();
    final root = await Directory(
      p.join(
        base.path,
        'baby-core-flow-${DateTime.now().microsecondsSinceEpoch}',
      ),
    ).create(recursive: true);
    final support = await Directory(
      p.join(root.path, 'support'),
    ).create(recursive: true);
    final inspections = await Directory(
      p.join(root.path, 'inspections'),
    ).create(recursive: true);
    final factory = _databaseFactory();
    final databasePath = p.join(support.path, 'app.sqlite');
    AppDatabase? database;
    addTearDown(() async {
      await database?.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    database = await AppDatabase.open(
      path: databasePath,
      databaseFactory: factory,
    );
    var babies = SqliteBabyRepository(database);
    var records = SqliteRecordRepository(database);
    final baby = await babies.create(
      const BabyDraft(name: '安安', birthDate: '2025-06-12', sex: '女'),
    );
    expect((await babies.getCurrent())?.name, '安安');

    final original = File(
      p.join(support.path, 'media', 'originals', 'first-smile.jpg'),
    );
    final thumbnail = File(
      p.join(support.path, 'media', 'thumbnails', 'first-smile.jpg'),
    );
    await original.create(recursive: true);
    await original.writeAsBytes([1, 2, 3, 4], flush: true);
    await thumbnail.create(recursive: true);
    await thumbnail.writeAsBytes([5, 6], flush: true);

    final inputs = <RecordType, NewRecordInput>{
      RecordType.moment: NewRecordInput(
        type: RecordType.moment,
        occurredAt: DateTime(2026, 7, 30, 23, 30).toUtc(),
        note: '第一次微笑',
        attachments: [
          NewAttachmentInput(
            mediaType: MediaType.image,
            filePath: original.path,
            thumbnailPath: thumbnail.path,
          ),
        ],
      ),
      RecordType.growth: NewRecordInput(
        type: RecordType.growth,
        occurredAt: DateTime(2026, 8, 1, 0, 30).toUtc(),
        note: '成长数据',
        details: const RecordDetails.growth(
          heightCm: 68.5,
          weightKg: 7.4,
          headCm: 42.1,
        ),
      ),
      RecordType.activity: NewRecordInput(
        type: RecordType.activity,
        occurredAt: DateTime(2026, 8, 2, 6, 30).toUtc(),
        note: '午睡',
        details: const RecordDetails.activity(
          activityType: ActivityType.sleep,
          durationMinutes: 95,
        ),
      ),
      RecordType.milestone: NewRecordInput(
        type: RecordType.milestone,
        occurredAt: DateTime(2026, 8, 3, 12).toUtc(),
        note: '里程碑',
        details: const RecordDetails.milestone(
          title: '第一次独站',
          presetKey: 'stand-alone',
        ),
      ),
    };

    final saved = <RecordType, TimelineRecord>{};
    for (final entry in inputs.entries) {
      final record = await records.create(entry.value);
      saved[entry.key] = record;
      expect((await records.get(record.id))?.type, entry.key);
    }

    final all = await records.list();
    expect(all.map((record) => record.type), [
      RecordType.milestone,
      RecordType.activity,
      RecordType.growth,
      RecordType.moment,
    ]);
    expect(
      (await records.list(
        types: {RecordType.growth, RecordType.milestone},
      )).map((record) => record.type),
      [RecordType.milestone, RecordType.growth],
    );
    final groups = groupRecordsByLocalDay(all);
    expect(
      groups.expand((group) => group.records).map((record) => record.id),
      all.map((record) => record.id),
    );
    expect(groups.map((group) => group.key).toSet(), {
      '2026-08-03',
      '2026-08-02',
      '2026-08-01',
      '2026-07-30',
    });

    for (final entry in saved.entries) {
      final existing = entry.value;
      final updated = await records.update(
        existing.id,
        _inputFrom(existing, note: 'edited-${entry.key.name}'),
      );
      expect(updated.note, 'edited-${entry.key.name}');

      final disposable = await records.create(inputs[entry.key]!);
      expect(await records.delete(disposable.id), disposable.attachments);
      expect(await records.get(disposable.id), isNull);
    }

    await database.close();
    database = await AppDatabase.open(
      path: databasePath,
      databaseFactory: factory,
    );
    babies = SqliteBabyRepository(database);
    records = SqliteRecordRepository(database);
    expect((await babies.get(baby.id))?.name, '安安');
    expect((await records.list()).length, 4);
    expect((await records.list()).map((record) => record.note).toSet(), {
      'edited-moment',
      'edited-growth',
      'edited-activity',
      'edited-milestone',
    });

    final gate = SerialDestructiveOperationGate();
    var nextBackupId = 0;
    final backup = LocalBackupService(
      databaseLifecycle: database,
      destructiveOperationGate: gate,
      databaseFactory: factory,
      applicationSupportDirectory: () async => support,
      inspectionDirectory: () async => inspections,
      createId: () => 'integration-${nextBackupId++}',
      shareArchive: (_) async {},
      now: () => DateTime.utc(2026, 8, 1, 12),
    );
    final archive = await backup.exportBackup();
    expect(await File(archive).exists(), isTrue);

    final media = LocalMediaService(
      applicationSupportDirectory: () async => support,
    );
    await clearAllData(
      database: database,
      mediaService: media,
      destructiveOperationGate: gate,
      queueOrphanCleanup: (_) async {},
    );
    expect(await babies.getCurrent(), isNull);
    expect(await records.list(), isEmpty);

    final inspected = await backup.inspect(archive);
    await backup.restore(inspected);
    expect((await babies.getCurrent())?.name, '安安');
    expect((await records.list()).length, 4);
    expect(await original.readAsBytes(), [1, 2, 3, 4]);
    expect(await thumbnail.readAsBytes(), [5, 6]);

    final beforeRejectedRestore = await records.list();
    final corrupt = File(p.join(root.path, 'corrupt.babygrowth.zip'));
    final archiveBytes = await File(archive).readAsBytes();
    await corrupt.writeAsBytes(
      archiveBytes.sublist(0, archiveBytes.length ~/ 2),
      flush: true,
    );
    await expectLater(
      backup.inspect(corrupt.path),
      throwsA(isA<BackupException>()),
    );
    expect(
      (await records.list()).map((record) => record.id).toList(),
      beforeRejectedRestore.map((record) => record.id).toList(),
    );
    expect((await babies.getCurrent())?.name, '安安');
  });
}

DatabaseFactory _databaseFactory() {
  if (Platform.isIOS || Platform.isAndroid) {
    return databaseFactorySqflitePlugin;
  }
  sqfliteFfiInit();
  return databaseFactoryFfi;
}

NewRecordInput _inputFrom(TimelineRecord record, {required String note}) =>
    NewRecordInput(
      type: record.type,
      occurredAt: record.occurredAt,
      note: note,
      details: record.details,
      attachments: [
        for (final attachment in record.attachments)
          NewAttachmentInput(
            id: attachment.id,
            mediaType: attachment.mediaType,
            filePath: attachment.filePath,
            thumbnailPath: attachment.thumbnailPath,
          ),
      ],
    );
