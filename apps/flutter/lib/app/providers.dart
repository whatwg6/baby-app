import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database_lifecycle.dart';
import '../data/repositories/baby_repository.dart';
import '../data/repositories/record_repository.dart';
import '../domain/destructive_operation_gate.dart';
import '../features/backup/domain/backup_service.dart';
import '../features/media/domain/media_service.dart';
import 'best_effort_dispose.dart';

class AppServices {
  const AppServices({
    required this.database,
    required this.babies,
    required this.records,
    required this.media,
    required this.backup,
  });

  final DatabaseLifecycle database;
  final BabyRepository babies;
  final RecordRepository records;
  final MediaService media;
  final BackupService backup;
}

class AppRuntime {
  factory AppRuntime({
    required AppServices services,
    required DestructiveOperationGate destructiveOperationGate,
    required Future<void> Function() clearAllData,
    required Future<void> Function() dispose,
  }) => AppRuntime._(
    dispose,
    services: services,
    destructiveOperationGate: destructiveOperationGate,
    clearAllData: clearAllData,
  );

  AppRuntime._(
    this._dispose, {
    required this.services,
    required this.destructiveOperationGate,
    required this.clearAllData,
  });

  final AppServices services;
  final DestructiveOperationGate destructiveOperationGate;
  final Future<void> Function() clearAllData;
  final Future<void> Function() _dispose;
  Future<void>? _disposeFuture;

  Future<void> dispose() => _disposeFuture ??= disposeBestEffort(_dispose);
}

final appRuntimeProvider = Provider<AppRuntime>((ref) {
  throw StateError('App runtime is unavailable before bootstrap completes.');
});

final appServicesProvider = Provider<AppServices>(
  (ref) => ref.watch(appRuntimeProvider).services,
  dependencies: [appRuntimeProvider],
);

final databaseProvider = Provider<DatabaseLifecycle>(
  (ref) => ref.watch(appServicesProvider).database,
  dependencies: [appServicesProvider],
);

final babyRepositoryProvider = Provider<BabyRepository>(
  (ref) => ref.watch(appServicesProvider).babies,
  dependencies: [appServicesProvider],
);

final recordRepositoryProvider = Provider<RecordRepository>(
  (ref) => ref.watch(appServicesProvider).records,
  dependencies: [appServicesProvider],
);

final mediaServiceProvider = Provider<MediaService>(
  (ref) => ref.watch(appServicesProvider).media,
  dependencies: [appServicesProvider],
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => ref.watch(appServicesProvider).backup,
  dependencies: [appServicesProvider],
);
