import 'dart:io';

import 'package:baby_growth_timeline/core/errors/app_exception.dart';
import 'package:baby_growth_timeline/data/database/app_database.dart';
import 'package:baby_growth_timeline/data/repositories/sqlite_baby_repository.dart';
import 'package:baby_growth_timeline/data/repositories/sqlite_record_repository.dart';
import 'package:baby_growth_timeline/domain/models/record_draft.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fixtures.dart';
import '../support/repository_contract.dart';

void main() {
  sqfliteFfiInit();

  late Directory temporaryDirectory;
  late AppDatabase appDatabase;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'baby-growth-repository-',
    );
    appDatabase = await AppDatabase.open(
      path: path.join(temporaryDirectory.path, 'timeline.sqlite'),
      databaseFactory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await appDatabase.close();
    await temporaryDirectory.delete(recursive: true);
  });

  group('SqliteBabyRepository contract', () {
    babyRepositoryContract(() async => SqliteBabyRepository(appDatabase));
  });

  group('SqliteRecordRepository contract', () {
    recordRepositoryContract(() async => SqliteRecordRepository(appDatabase));
  });

  test('persists instants as canonical UTC ISO 8601 strings', () async {
    final repository = SqliteRecordRepository(appDatabase);
    final created = await repository.create(momentInputFixture());

    final rows = await appDatabase.read(
      (database) => database.query(
        'records',
        columns: ['occurred_at'],
        where: 'id = ?',
        whereArgs: [created.id],
      ),
    );
    expect(rows.single['occurred_at'], '2026-07-31T14:15:00.000Z');
    expect(created.occurredAt, DateTime.utc(2026, 7, 31, 14, 15));
  });

  test(
    'rejects details whose subtype does not match the record type',
    () async {
      final repository = SqliteRecordRepository(appDatabase);

      await expectLater(
        repository.create(
          NewRecordInput(
            type: RecordType.growth,
            occurredAt: fixtureOccurredAt,
            details: const RecordDetails.milestone(title: '错误详情'),
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await repository.list(), isEmpty);
    },
  );

  test('delete returns attachment metadata captured before cascade', () async {
    final repository = SqliteRecordRepository(appDatabase);
    final created = await repository.create(momentInputFixture());

    final removed = await repository.delete(created.id);

    expect(removed, created.attachments);
    final rows = await appDatabase.read(
      (database) => database.query('attachments'),
    );
    expect(rows, isEmpty);
  });
}
