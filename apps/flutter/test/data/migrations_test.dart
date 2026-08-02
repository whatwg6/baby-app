import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:baby_growth_timeline/data/database/app_database.dart';
import 'package:baby_growth_timeline/data/database/database_lifecycle.dart';
import 'package:baby_growth_timeline/data/database/migrations.dart';
import 'package:baby_growth_timeline/data/repositories/sqlite_record_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fixtures.dart';

void main() {
  sqfliteFfiInit();

  late Directory temporaryDirectory;
  late String databasePath;
  late AppDatabase appDatabase;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'baby-growth-migration-',
    );
    databasePath = path.join(temporaryDirectory.path, 'timeline.sqlite');
    appDatabase = await AppDatabase.open(
      path: databasePath,
      databaseFactory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await appDatabase.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('version 1 migration creates the complete constrained schema', () async {
    final version = await appDatabase.read(
      (database) => database.rawQuery('PRAGMA user_version'),
    );
    expect(version.single['user_version'], schemaVersion);

    final tableRows = await appDatabase.read(
      (database) => database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ),
    );
    expect(tableRows.map((row) => row['name']).toSet(), {
      'baby',
      'records',
      'growth_details',
      'activity_details',
      'milestone_details',
      'attachments',
    });

    final foreignKeys = await appDatabase.read(
      (database) => database.rawQuery('PRAGMA foreign_keys'),
    );
    expect(foreignKeys.single['foreign_keys'], 1);

    final indexes = await appDatabase.read(
      (database) => database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      ),
    );
    expect(
      indexes.map((row) => row['name']),
      contains('records_occurred_at_desc_idx'),
    );

    for (final table in [
      'growth_details',
      'activity_details',
      'milestone_details',
      'attachments',
    ]) {
      final keys = await appDatabase.read(
        (database) => database.rawQuery('PRAGMA foreign_key_list($table)'),
      );
      expect(keys.single['table'], 'records');
      expect(keys.single['from'], 'record_id');
      expect(keys.single['on_delete'], 'CASCADE');
    }
  });

  test('every detail table permits only one row per record', () async {
    await appDatabase.write((database) async {
      await database.insert('records', {
        'id': 'record-1',
        'type': 'growth',
        'occurred_at': '2026-01-01T00:00:00.000Z',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
    });

    final detailRows = {
      'growth_details': {'height_cm': 70.0},
      'activity_details': {'activity_type': 'sleep'},
      'milestone_details': {'title': '第一次独站'},
    };
    for (final entry in detailRows.entries) {
      await appDatabase.write(
        (database) => database.insert(entry.key, {
          'id': '${entry.key}-1',
          'record_id': 'record-1',
          ...entry.value,
        }),
      );
      await expectLater(
        appDatabase.write(
          (database) => database.insert(entry.key, {
            'id': '${entry.key}-2',
            'record_id': 'record-1',
            ...entry.value,
          }),
        ),
        throwsA(isA<DatabaseException>()),
        reason: '${entry.key}.record_id must be unique',
      );
    }
  });

  test('deleting a record cascades to every dependent row', () async {
    await appDatabase.write((database) async {
      await database.insert('records', {
        'id': 'record-1',
        'type': 'growth',
        'occurred_at': '2026-01-01T00:00:00.000Z',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      await database.insert('growth_details', {
        'id': 'detail-1',
        'record_id': 'record-1',
        'height_cm': 70.0,
      });
      await database.insert('activity_details', {
        'id': 'detail-2',
        'record_id': 'record-1',
        'activity_type': 'sleep',
      });
      await database.insert('milestone_details', {
        'id': 'detail-3',
        'record_id': 'record-1',
        'title': '第一次独站',
      });
      await database.insert('attachments', {
        'id': 'attachment-1',
        'record_id': 'record-1',
        'media_type': 'image',
        'file_path': '/media/photo.jpg',
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      await database.delete(
        'records',
        where: 'id = ?',
        whereArgs: ['record-1'],
      );
    });

    for (final table in [
      'growth_details',
      'activity_details',
      'milestone_details',
      'attachments',
    ]) {
      final rows = await appDatabase.read((database) => database.query(table));
      expect(rows, isEmpty, reason: '$table must cascade with its record');
    }
  });

  test(
    'checkpoints then closes before callback and failure migrates on reopen',
    () async {
      await appDatabase.write((database) async {
        await database.insert('baby', {
          'id': 'baby-1',
          'name': '宝宝',
          'birth_date': '2025-06-12',
          'created_at': '2026-01-01T00:00:00.000Z',
          'updated_at': '2026-01-01T00:00:00.000Z',
        });
      });
      expect(appDatabase.isOpen, isTrue);

      await expectLater(
        appDatabase.withClosedDatabase<void>((closedPath) async {
          expect(closedPath, databasePath);
          expect(appDatabase.isOpen, isFalse);
          final wal = File('$closedPath-wal');
          expect(!wal.existsSync() || wal.lengthSync() == 0, isTrue);
          await databaseFactoryFfi.deleteDatabase(closedPath);
          throw StateError('export failed');
        }),
        throwsStateError,
      );

      expect(appDatabase.isOpen, isTrue);
      final version = await appDatabase.read(
        (database) => database.rawQuery('PRAGMA user_version'),
      );
      expect(version.single['user_version'], schemaVersion);
      final tables = await appDatabase.read(
        (database) => database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ),
      );
      expect(tables.map((row) => row['name']), contains('attachments'));
    },
  );

  test(
    'repository work waits for a closed callback and uses reopened data',
    () async {
      final callbackEntered = Completer<void>();
      final releaseCallback = Completer<void>();
      final lifecycle = appDatabase.withClosedDatabase<void>((_) async {
        callbackEntered.complete();
        await releaseCallback.future;
      });
      await callbackEntered.future;

      final repository = SqliteRecordRepository(appDatabase);
      final create = Future.sync(() => repository.create(momentInputFixture()));
      var createCompleted = false;
      Object? createError;
      unawaited(
        create.then<void>(
          (_) => createCompleted = true,
          onError: (Object error, StackTrace _) {
            createCompleted = true;
            createError = error;
          },
        ),
      );

      try {
        await Future<void>.delayed(Duration.zero);
        expect(createCompleted, isFalse);
      } finally {
        releaseCallback.complete();
        await lifecycle;
      }

      final created = await create;
      expect(createError, isNull);
      expect(await repository.get(created.id), created);
    },
  );

  test('closed lifecycle waits for an active database operation', () async {
    final operationEntered = Completer<void>();
    final releaseOperation = Completer<void>();
    final operation = appDatabase.read((database) async {
      await database.rawQuery('PRAGMA user_version');
      operationEntered.complete();
      await releaseOperation.future;
      return database.rawQuery('PRAGMA user_version');
    });
    await operationEntered.future;

    final callbackEntered = Completer<void>();
    final lifecycle = appDatabase.withClosedDatabase<void>((_) async {
      callbackEntered.complete();
    });

    try {
      final enteredBeforeRelease = await Future.any([
        callbackEntered.future.then((_) => true),
        Future.delayed(const Duration(milliseconds: 250), () => false),
      ]);
      expect(enteredBeforeRelease, isFalse);
      expect(appDatabase.isOpen, isTrue);
    } finally {
      releaseOperation.complete();
    }

    final rows = await operation;
    await lifecycle.timeout(const Duration(seconds: 3));
    expect(rows.single['user_version'], schemaVersion);
  });

  test(
    'public reopen and a second lifecycle wait outside the callback',
    () async {
      final callbackEntered = Completer<void>();
      final releaseCallback = Completer<void>();
      final firstLifecycle = appDatabase.withClosedDatabase<void>((_) async {
        callbackEntered.complete();
        await releaseCallback.future;
      });
      await callbackEntered.future;

      var reopenCompleted = false;
      final reopen = appDatabase.reopen();
      unawaited(reopen.then((_) => reopenCompleted = true));

      var secondCallbackEntered = false;
      final secondLifecycle = Future.sync(
        () => appDatabase.withClosedDatabase<void>((_) async {
          secondCallbackEntered = true;
        }),
      );
      Object? secondLifecycleError;
      unawaited(
        secondLifecycle.then<void>(
          (_) {},
          onError: (Object error, StackTrace _) {
            secondLifecycleError = error;
          },
        ),
      );

      try {
        await Future<void>.delayed(Duration.zero);
        expect(reopenCompleted, isFalse);
        expect(secondCallbackEntered, isFalse);
        expect(appDatabase.isOpen, isFalse);
      } finally {
        releaseCallback.complete();
      }

      await firstLifecycle.timeout(const Duration(seconds: 3));
      await reopen.timeout(const Duration(seconds: 3));
      await secondLifecycle.timeout(const Duration(seconds: 3));
      expect(secondLifecycleError, isNull);
      expect(secondCallbackEntered, isTrue);
      expect(appDatabase.isOpen, isTrue);
    },
  );

  test('closed lifecycle preserves callback and reopen failures', () async {
    final failingFactory = _FailingOpenDatabaseFactory(databaseFactoryFfi);
    final failingDatabase = await AppDatabase.open(
      path: path.join(temporaryDirectory.path, 'reopen-failure.sqlite'),
      databaseFactory: failingFactory,
    );
    failingFactory.failNextOpen = true;

    DatabaseLifecycleReopenException? failure;
    try {
      await failingDatabase.withClosedDatabase<void>((_) async {
        throw StateError('callback failed');
      });
    } on DatabaseLifecycleReopenException catch (error) {
      failure = error;
    }

    expect(failure, isNotNull);
    expect(failure!.operationError, isA<StateError>());
    expect(failure.reopenError, isA<StateError>());
    expect(failingDatabase.isOpen, isFalse);

    await failingDatabase.reopen();
    await failingDatabase.close();
  });
}

class _FailingOpenDatabaseFactory implements DatabaseFactory {
  _FailingOpenDatabaseFactory(this.delegate);

  final DatabaseFactory delegate;
  bool failNextOpen = false;

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) {
    if (failNextOpen) {
      failNextOpen = false;
      throw StateError('reopen failed');
    }
    return delegate.openDatabase(path, options: options);
  }

  @override
  Future<bool> databaseExists(String path) => delegate.databaseExists(path);

  @override
  Future<void> deleteDatabase(String path) => delegate.deleteDatabase(path);

  @override
  Future<String> getDatabasesPath() => delegate.getDatabasesPath();

  @override
  Future<Uint8List> readDatabaseBytes(String path) =>
      delegate.readDatabaseBytes(path);

  @override
  Future<void> setDatabasesPath(String path) => delegate.setDatabasesPath(path);

  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) =>
      delegate.writeDatabaseBytes(path, bytes);
}
