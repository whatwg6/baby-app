import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database/app_database.dart';
import '../data/database/migrations.dart';
import '../data/repositories/sqlite_baby_repository.dart';
import '../data/repositories/sqlite_record_repository.dart';
import '../domain/destructive_operation_gate.dart';
import '../features/backup/data/local_backup_service.dart';
import '../features/backup/presentation/backup_actions.dart' as backup_actions;
import '../features/media/data/local_media_service.dart';
import 'best_effort_dispose.dart';
import 'providers.dart';

abstract interface class BootstrapEnvironment {
  Future<void> ensureDirectories();

  Future<void> recoverLegacyRollback();

  Future<void> openDatabase();

  Future<void> migrateDatabase();

  AppServices buildServices(DestructiveOperationGate gate);

  Future<void> clearAllData(
    AppServices services,
    DestructiveOperationGate gate,
  );

  Future<void> removeStagingFiles();

  Future<Set<String>> referencedMediaPaths(AppServices services);

  Future<void> removeOrphans(AppServices services, Set<String> referencedPaths);

  Future<void> removeExpiredExports(AppServices services, Duration maxAge);

  Future<void> logDebugError(
    String operation,
    Object error,
    StackTrace stackTrace,
  );

  Future<void> dispose();
}

class BootstrapResult {
  const BootstrapResult._({
    this.runtime,
    this.fatalError,
    this.fatalStackTrace,
  });

  const BootstrapResult.ready(AppRuntime runtime) : this._(runtime: runtime);

  const BootstrapResult.failed(Object error, StackTrace stackTrace)
    : this._(fatalError: error, fatalStackTrace: stackTrace);

  final AppRuntime? runtime;
  final Object? fatalError;
  final StackTrace? fatalStackTrace;

  AppServices? get services => runtime?.services;
  bool get canContinue => services != null;

  Future<void> dispose() async => runtime?.dispose();
}

Future<BootstrapResult> bootstrapApp(BootstrapEnvironment environment) async {
  late final AppServices services;
  final destructiveOperationGate = SerialDestructiveOperationGate();
  try {
    await environment.ensureDirectories();
    await environment.recoverLegacyRollback();
    await environment.openDatabase();
    await environment.migrateDatabase();
    services = environment.buildServices(destructiveOperationGate);
  } catch (error, stackTrace) {
    await _logBestEffort(environment, 'fatal bootstrap', error, stackTrace);
    await disposeBestEffort(environment.dispose);
    return BootstrapResult.failed(error, stackTrace);
  }

  await _runNonFatal(
    environment,
    'media staging cleanup',
    environment.removeStagingFiles,
  );
  await _runNonFatal(environment, 'media orphan cleanup', () async {
    final referencedPaths = await environment.referencedMediaPaths(services);
    await environment.removeOrphans(services, referencedPaths);
  });
  await _runNonFatal(
    environment,
    'backup export cleanup',
    () => environment.removeExpiredExports(services, const Duration(hours: 24)),
  );
  return BootstrapResult.ready(
    AppRuntime(
      services: services,
      destructiveOperationGate: destructiveOperationGate,
      clearAllData: () =>
          environment.clearAllData(services, destructiveOperationGate),
      dispose: environment.dispose,
    ),
  );
}

Future<void> _runNonFatal(
  BootstrapEnvironment environment,
  String operation,
  Future<void> Function() work,
) async {
  try {
    await work();
  } catch (error, stackTrace) {
    await _logBestEffort(environment, operation, error, stackTrace);
  }
}

Future<void> _logBestEffort(
  BootstrapEnvironment environment,
  String operation,
  Object error,
  StackTrace stackTrace,
) async {
  try {
    await environment.logDebugError(operation, error, stackTrace);
  } catch (_) {
    // Logging must never replace the original bootstrap outcome.
  }
}

class LocalBootstrapEnvironment implements BootstrapEnvironment {
  LocalBootstrapEnvironment({
    DatabaseFactory? databaseFactory,
    Future<Directory> Function()? applicationSupportDirectory,
    Future<Directory> Function()? temporaryDirectory,
    LocalDebugLogger? debugLogger,
  }) : _databaseFactory = databaseFactory ?? databaseFactorySqflitePlugin,
       _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _debugLogger =
           debugLogger ??
           LocalDebugLogger(
             applicationSupportDirectory:
                 applicationSupportDirectory ?? getApplicationSupportDirectory,
           );

  final DatabaseFactory _databaseFactory;
  final Future<Directory> Function() _applicationSupportDirectory;
  final Future<Directory> Function() _temporaryDirectory;
  final LocalDebugLogger _debugLogger;
  Directory? _supportDirectory;
  String? _databasePath;
  AppDatabase? _database;
  AppServices? _services;

  Directory get _requiredSupportDirectory =>
      _supportDirectory ??
      (throw StateError('Application directories have not been created.'));

  String get _requiredDatabasePath =>
      _databasePath ??
      (throw StateError('Application directories have not been created.'));

  AppDatabase get _requiredDatabase =>
      _database ?? (throw StateError('Database has not been opened.'));

  @override
  Future<void> ensureDirectories() async {
    final support = await _applicationSupportDirectory();
    await support.create(recursive: true);
    for (final relativePath in const [
      'media/originals',
      'media/thumbnails',
      'staging',
      'backup-exports',
      'backup-work',
      'backup-rollbacks',
      'debug',
    ]) {
      await Directory(
        p.join(support.path, relativePath),
      ).create(recursive: true);
    }
    final databasePath = p.join(
      await _databaseFactory.getDatabasesPath(),
      'baby_growth_timeline.sqlite',
    );
    await Directory(p.dirname(databasePath)).create(recursive: true);
    _supportDirectory = support;
    _databasePath = databasePath;
  }

  @override
  Future<void> recoverLegacyRollback() => recoverLegacyRollbackDirectories(
    applicationSupportDirectory: _requiredSupportDirectory,
    databasePath: _requiredDatabasePath,
  );

  @override
  Future<void> openDatabase() async {
    _database = await AppDatabase.open(
      path: _requiredDatabasePath,
      databaseFactory: _databaseFactory,
    );
  }

  @override
  Future<void> migrateDatabase() async {
    try {
      final rows = await _requiredDatabase.read(
        (database) => database.rawQuery('PRAGMA user_version'),
      );
      final version = rows.single.values.single as int;
      if (version != schemaVersion) {
        throw StateError(
          'Database migration did not reach schema version $schemaVersion.',
        );
      }
    } catch (_) {
      await _database?.close();
      _database = null;
      rethrow;
    }
  }

  @override
  AppServices buildServices(DestructiveOperationGate gate) {
    final existing = _services;
    if (existing != null) return existing;
    final database = _requiredDatabase;
    final media = LocalMediaService(
      applicationSupportDirectory: () async => _requiredSupportDirectory,
    );
    final services = AppServices(
      database: database,
      babies: SqliteBabyRepository(database),
      records: SqliteRecordRepository(database),
      media: media,
      backup: LocalBackupService(
        databaseLifecycle: database,
        destructiveOperationGate: gate,
        databaseFactory: _databaseFactory,
        applicationSupportDirectory: () async => _requiredSupportDirectory,
        inspectionDirectory: _temporaryDirectory,
      ),
    );
    _services = services;
    return services;
  }

  @override
  Future<void> clearAllData(
    AppServices services,
    DestructiveOperationGate gate,
  ) => backup_actions.clearAllData(
    database: _requiredDatabase,
    mediaService: services.media,
    destructiveOperationGate: gate,
    queueOrphanCleanup: (_) async {},
  );

  @override
  Future<void> removeStagingFiles() async {
    final staging = Directory(
      p.join(_requiredSupportDirectory.path, 'staging'),
    );
    if (await FileSystemEntity.type(staging.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      await staging.create(recursive: true);
      return;
    }
    await for (final entity in staging.list(followLinks: false)) {
      await entity.delete(recursive: entity is Directory);
    }
  }

  @override
  Future<Set<String>> referencedMediaPaths(AppServices services) async {
    final paths = <String>{};
    final baby = await services.babies.getCurrent();
    final avatarPath = baby?.avatarPath;
    if (avatarPath != null && avatarPath.isNotEmpty) paths.add(avatarPath);
    for (final record in await services.records.list()) {
      for (final attachment in record.attachments) {
        paths.add(attachment.filePath);
        final thumbnailPath = attachment.thumbnailPath;
        if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
          paths.add(thumbnailPath);
        }
      }
    }
    return paths;
  }

  @override
  Future<void> removeOrphans(
    AppServices services,
    Set<String> referencedPaths,
  ) => services.media.removeOrphans(referencedPaths);

  @override
  Future<void> removeExpiredExports(AppServices services, Duration maxAge) =>
      services.backup.removeExpiredExports(maxAge);

  @override
  Future<void> logDebugError(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) => _debugLogger.write(operation, error, stackTrace);

  @override
  Future<void> dispose() async {
    _services = null;
    final database = _database;
    _database = null;
    await database?.close();
  }
}

Future<int> recoverLegacyRollbackDirectories({
  required Directory applicationSupportDirectory,
  required String databasePath,
}) async {
  final rollbackRoot = Directory(
    p.join(applicationSupportDirectory.path, 'backup-rollbacks'),
  );
  if (await FileSystemEntity.type(rollbackRoot.path, followLinks: false) ==
      FileSystemEntityType.notFound) {
    return 0;
  }
  final candidates = <Directory>[];
  await for (final entity in rollbackRoot.list(followLinks: false)) {
    if (entity is Directory &&
        p.basename(entity.path).startsWith('rollback-')) {
      candidates.add(entity);
    }
  }
  if (candidates.length > 1) {
    throw StateError(
      'Multiple interrupted backup restores require manual recovery.',
    );
  }
  if (candidates.isEmpty) return 0;

  final rollback = candidates.single;
  final rollbackDatabase = File(p.join(rollback.path, 'database', 'app.db'));
  final rollbackMedia = Directory(p.join(rollback.path, 'media'));
  final hasDatabase =
      await FileSystemEntity.type(rollbackDatabase.path, followLinks: false) ==
      FileSystemEntityType.file;
  final hasMedia =
      await FileSystemEntity.type(rollbackMedia.path, followLinks: false) ==
      FileSystemEntityType.directory;

  if (hasDatabase) {
    for (final path in [
      databasePath,
      '$databasePath-wal',
      '$databasePath-shm',
    ]) {
      final entityType = await FileSystemEntity.type(path, followLinks: false);
      if (entityType != FileSystemEntityType.notFound) {
        await File(path).delete();
      }
    }
    await rollbackDatabase.rename(databasePath);
  }
  if (hasMedia) {
    final media = Directory(p.join(applicationSupportDirectory.path, 'media'));
    if (await FileSystemEntity.type(media.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      await media.delete(recursive: true);
    }
    await rollbackMedia.rename(media.path);
  }
  await rollback.delete(recursive: true);
  return 1;
}

class LocalDebugLogger {
  LocalDebugLogger({
    Future<Directory> Function()? applicationSupportDirectory,
    DateTime Function()? now,
  }) : _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now;

  final Future<Directory> Function() _applicationSupportDirectory;
  final DateTime Function() _now;

  Future<void> write(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) async {
    final support = await _applicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'debug'));
    await directory.create(recursive: true);
    final message =
        '${_now().toUtc().toIso8601String()} [$operation] '
        '$error\n$stackTrace\n';
    await File(
      p.join(directory.path, 'app.log'),
    ).writeAsString(message, mode: FileMode.append, flush: true);
  }
}

void installLocalFlutterErrorLogging(LocalDebugLogger logger) {
  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    if (previousFlutterHandler != null) {
      previousFlutterHandler(details);
    } else {
      FlutterError.presentError(details);
    }
    unawaited(
      logger
          .write(
            'flutter framework',
            details.exception,
            details.stack ?? StackTrace.current,
          )
          .catchError((_) {}),
    );
  };
}
