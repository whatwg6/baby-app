import 'dart:async';

import 'package:path/path.dart' as path_util;
import 'package:sqflite/sqflite.dart';

import 'database_lifecycle.dart';
import 'migrations.dart';

class AppDatabase implements DatabaseLifecycle {
  AppDatabase._({required this.path, required this._databaseFactory});

  final String path;
  final DatabaseFactory _databaseFactory;
  final _gate = _ExclusiveGate();
  Database? _database;

  static Future<AppDatabase> open({
    String? path,
    DatabaseFactory? databaseFactory,
  }) async {
    final resolvedFactory = databaseFactory ?? databaseFactorySqflitePlugin;
    final resolvedPath =
        path ??
        path_util.join(
          await resolvedFactory.getDatabasesPath(),
          'baby_growth_timeline.sqlite',
        );
    final appDatabase = AppDatabase._(
      path: resolvedPath,
      databaseFactory: resolvedFactory,
    );
    await appDatabase.reopen();
    return appDatabase;
  }

  bool get isOpen => _database?.isOpen ?? false;

  Future<T> read<T>(Future<T> Function(DatabaseExecutor database) work) =>
      _gate.run(() => work(_requireDatabase()));

  Future<T> write<T>(Future<T> Function(DatabaseExecutor database) work) =>
      _gate.run(() => work(_requireDatabase()));

  Future<T> transaction<T>(Future<T> Function(Transaction transaction) work) =>
      _gate.run(() => _requireDatabase().transaction(work));

  @override
  Future<T> withClosedDatabase<T>(
    Future<T> Function(String databasePath) work,
  ) => _gate.run(() => _withClosedDatabase(work));

  Future<T> _withClosedDatabase<T>(
    Future<T> Function(String databasePath) work,
  ) async {
    final database = _requireDatabase();
    await database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    await database.close();
    _database = null;

    late T result;
    Object? operationError;
    StackTrace? operationStackTrace;
    try {
      result = await work(path);
    } catch (error, stackTrace) {
      operationError = error;
      operationStackTrace = stackTrace;
    }
    try {
      await _reopenUnlocked();
    } catch (reopenError, reopenStackTrace) {
      throw DatabaseLifecycleReopenException(
        operationError: operationError,
        operationStackTrace: operationStackTrace,
        reopenError: reopenError,
        reopenStackTrace: reopenStackTrace,
      );
    }
    if (operationError != null) {
      Error.throwWithStackTrace(operationError, operationStackTrace!);
    }
    return result;
  }

  @override
  Future<void> reopen() => _gate.run(_reopenUnlocked);

  Future<void> _reopenUnlocked() async {
    if (isOpen) {
      return;
    }
    _database = await _databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
          await database.execute('PRAGMA journal_mode = WAL');
        },
        onCreate: (database, version) => migrateDatabase(database, 0, version),
        onUpgrade: migrateDatabase,
      ),
    );
  }

  Future<void> close() => _gate.run(_closeUnlocked);

  Future<void> _closeUnlocked() async {
    final database = _database;
    _database = null;
    if (database?.isOpen ?? false) {
      await database!.close();
    }
  }

  Database _requireDatabase() {
    final database = _database;
    if (database == null || !database.isOpen) {
      throw StateError('Database is closed.');
    }
    return database;
  }
}

final class _ExclusiveGate {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final predecessor = _tail;
    final release = Completer<void>();
    _tail = release.future;

    return predecessor.then((_) => operation()).whenComplete(release.complete);
  }
}
