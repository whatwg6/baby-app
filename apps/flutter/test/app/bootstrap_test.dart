import 'dart:async';
import 'dart:io';

import 'package:baby_growth_timeline/app/app.dart';
import 'package:baby_growth_timeline/app/bootstrap.dart';
import 'package:baby_growth_timeline/app/providers.dart';
import 'package:baby_growth_timeline/data/database/database_lifecycle.dart';
import 'package:baby_growth_timeline/data/repositories/baby_repository.dart';
import 'package:baby_growth_timeline/data/repositories/record_repository.dart';
import 'package:baby_growth_timeline/domain/destructive_operation_gate.dart';
import 'package:baby_growth_timeline/domain/models/attachment.dart';
import 'package:baby_growth_timeline/domain/models/baby.dart';
import 'package:baby_growth_timeline/domain/models/record_draft.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';
import 'package:baby_growth_timeline/features/backup/domain/backup_service.dart';
import 'package:baby_growth_timeline/features/media/domain/media_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

void main() {
  group('bootstrapApp', () {
    test('bootstraps services in safe order', () async {
      final environment = _RecordingEnvironment();

      final result = await bootstrapApp(environment);

      expect(result.canContinue, isTrue);
      expect(result.services, same(environment.appServices));
      expect(environment.events, [
        'directories.ensureCreated',
        'rollback.recover',
        'database.open',
        'database.migrate',
        'services.build',
        'media.removeStagingFiles',
        'media.referencedPaths',
        'media.removeOrphans:/media/referenced.jpg',
        'backup.removeExpiredExports:24',
      ]);
    });

    test('migration failure returns a state that cannot continue', () async {
      final environment = _RecordingEnvironment(failAt: 'database.migrate');

      final result = await bootstrapApp(environment);

      expect(result.canContinue, isFalse);
      expect(result.services, isNull);
      expect(result.fatalError, isA<StateError>());
      expect(environment.events, [
        'directories.ensureCreated',
        'rollback.recover',
        'database.open',
        'database.migrate',
        'debug:fatal bootstrap',
        'environment.dispose',
      ]);
    });

    test('fatal service construction closes the opened environment', () async {
      final environment = _RecordingEnvironment(failAt: 'services.build');

      final result = await bootstrapApp(environment);

      expect(result.canContinue, isFalse);
      expect(environment.events, [
        'directories.ensureCreated',
        'rollback.recover',
        'database.open',
        'database.migrate',
        'services.build',
        'debug:fatal bootstrap',
        'environment.dispose',
      ]);
    });

    test(
      'throwing fatal dispose preserves the original bootstrap error',
      () async {
        final environment = _RecordingEnvironment(
          failAt: 'database.migrate',
          disposeError: StateError('dispose failed'),
        );

        final result = await bootstrapApp(environment);

        expect(result.canContinue, isFalse);
        expect(
          result.fatalError,
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'database.migrate failed',
          ),
        );
        expect(environment.events, [
          'directories.ensureCreated',
          'rollback.recover',
          'database.open',
          'database.migrate',
          'debug:fatal bootstrap',
          'environment.dispose',
        ]);
      },
    );

    test(
      'orphan cleanup failure is logged and does not block startup',
      () async {
        final environment = _RecordingEnvironment(
          failAt: 'media.removeOrphans',
        );

        final result = await bootstrapApp(environment);

        expect(result.canContinue, isTrue);
        expect(environment.events, contains('debug:media orphan cleanup'));
        expect(environment.events, contains('backup.removeExpiredExports:24'));
      },
    );

    test(
      'staging cleanup failure is logged and does not block startup',
      () async {
        final environment = _RecordingEnvironment(
          failAt: 'media.removeStagingFiles',
        );

        final result = await bootstrapApp(environment);

        expect(result.canContinue, isTrue);
        expect(environment.events, contains('debug:media staging cleanup'));
        expect(
          environment.events,
          contains('media.removeOrphans:/media/referenced.jpg'),
        );
      },
    );

    test('checks rollback recovery before opening the database', () async {
      final environment = _RecordingEnvironment(rollbackDetected: true);

      final result = await bootstrapApp(environment);

      expect(result.canContinue, isTrue);
      expect(
        environment.events.indexOf('rollback.restore'),
        lessThan(environment.events.indexOf('database.open')),
      );
    });

    test(
      'restore and clear-all share one destructive operation gate',
      () async {
        final environment = _SerialEnvironment();
        final result = await bootstrapApp(environment);

        final restore = environment.backup.runRestore();
        await environment.restoreStarted.future;
        final clear = result.runtime!.clearAllData();
        await Future<void>.delayed(Duration.zero);

        expect(environment.events, ['restore.start']);
        environment.releaseRestore.complete();
        await Future.wait([restore, clear]);
        expect(environment.events, [
          'restore.start',
          'restore.end',
          'clear.start',
          'clear.end',
        ]);
      },
    );
  });

  test('legacy rollback recovery restores database and media', () async {
    final root = await Directory.systemTemp.createTemp('bootstrap-rollback-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final support = Directory(p.join(root.path, 'support'));
    final database = File(p.join(root.path, 'databases', 'app.sqlite'));
    final currentMedia = File(p.join(support.path, 'media', 'current.jpg'));
    final rollback = Directory(
      p.join(support.path, 'backup-rollbacks', 'rollback-left-behind'),
    );
    await database.parent.create(recursive: true);
    await database.writeAsString('replacement database');
    await currentMedia.parent.create(recursive: true);
    await currentMedia.writeAsString('replacement media');
    await File(p.join(rollback.path, 'database', 'app.db'))
        .create(recursive: true)
        .then((file) => file.writeAsString('original database'));
    await File(p.join(rollback.path, 'media', 'original.jpg'))
        .create(recursive: true)
        .then((file) => file.writeAsString('original media'));

    final recovered = await recoverLegacyRollbackDirectories(
      applicationSupportDirectory: support,
      databasePath: database.path,
    );

    expect(recovered, 1);
    expect(await database.readAsString(), 'original database');
    expect(
      await File(p.join(support.path, 'media', 'original.jpg')).readAsString(),
      'original media',
    );
    expect(await currentMedia.exists(), isFalse);
    expect(await rollback.exists(), isFalse);
  });

  test('providers expose only the stable service interfaces', () {
    final services = _services();
    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(services)],
    );
    addTearDown(container.dispose);

    expect(container.read(databaseProvider), same(services.database));
    expect(container.read(babyRepositoryProvider), same(services.babies));
    expect(container.read(recordRepositoryProvider), same(services.records));
    expect(container.read(mediaServiceProvider), same(services.media));
    expect(container.read(backupServiceProvider), same(services.backup));
  });

  testWidgets('shows branded startup content until bootstrap completes', (
    tester,
  ) async {
    final pending = Completer<BootstrapResult>();

    await tester.pumpWidget(
      BabyTimelineBootstrap(bootstrap: () => pending.future),
    );

    expect(find.text('宝宝成长记'), findsOneWidget);
    expect(find.text('正在打开本地数据…'), findsOneWidget);
    expect(find.text('时间轴'), findsNothing);
  });

  testWidgets('fatal bootstrap displays a retryable error boundary', (
    tester,
  ) async {
    var attempts = 0;
    Future<BootstrapResult> bootstrap() async {
      attempts += 1;
      return BootstrapResult.failed(
        StateError('database unavailable'),
        StackTrace.current,
      );
    }

    await tester.pumpWidget(BabyTimelineBootstrap(bootstrap: bootstrap));
    await tester.pumpAndSettle();

    expect(find.text('无法打开本地数据'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('时间轴'), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets('an outdated bootstrap result disposes its own runtime', (
    tester,
  ) async {
    final first = Completer<BootstrapResult>();
    var staleDisposeCount = 0;
    final staleRuntime = AppRuntime(
      services: _services(),
      destructiveOperationGate: SerialDestructiveOperationGate(),
      clearAllData: () async {},
      dispose: () async => staleDisposeCount += 1,
    );

    await tester.pumpWidget(
      BabyTimelineBootstrap(
        key: const ValueKey('bootstrap'),
        bootstrap: () => first.future,
      ),
    );
    await tester.pumpWidget(
      BabyTimelineBootstrap(
        key: const ValueKey('bootstrap'),
        bootstrap: () async => BootstrapResult.failed(
          StateError('new attempt failed'),
          StackTrace.current,
        ),
      ),
    );
    await tester.pumpAndSettle();

    first.complete(BootstrapResult.ready(staleRuntime));
    await tester.pumpAndSettle();

    expect(staleDisposeCount, 1);
    expect(find.text('无法打开本地数据'), findsOneWidget);
  });

  testWidgets('throwing stale dispose does not disturb the current result', (
    tester,
  ) async {
    final first = Completer<BootstrapResult>();
    final staleRuntime = AppRuntime(
      services: _services(),
      destructiveOperationGate: SerialDestructiveOperationGate(),
      clearAllData: () async {},
      dispose: () async => throw StateError('stale dispose failed'),
    );
    final currentBaby = Baby(
      id: 'current-baby',
      name: '当前宝宝',
      birthDate: '2025-06-12',
      createdAt: DateTime.utc(2025, 6, 12),
      updatedAt: DateTime.utc(2025, 6, 12),
    );

    await tester.pumpWidget(
      BabyTimelineBootstrap(
        key: const ValueKey('bootstrap'),
        bootstrap: () => first.future,
      ),
    );
    await tester.pumpWidget(
      BabyTimelineBootstrap(
        key: const ValueKey('bootstrap'),
        bootstrap: () async => BootstrapResult.ready(
          AppRuntime(
            services: _services(baby: currentBaby),
            destructiveOperationGate: SerialDestructiveOperationGate(),
            clearAllData: () async {},
            dispose: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    first.complete(BootstrapResult.ready(staleRuntime));
    await tester.pumpAndSettle();

    expect(find.text('当前宝宝'), findsOneWidget);
  });

  testWidgets('disposing a ready bootstrap releases its runtime', (
    tester,
  ) async {
    var disposeCount = 0;
    final runtime = AppRuntime(
      services: _services(),
      destructiveOperationGate: SerialDestructiveOperationGate(),
      clearAllData: () async {},
      dispose: () async => disposeCount += 1,
    );
    await tester.pumpWidget(
      BabyTimelineBootstrap(
        bootstrap: () async => BootstrapResult.ready(runtime),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(disposeCount, 1);
  });

  testWidgets('throwing dispose is isolated when bootstrap unmounts', (
    tester,
  ) async {
    final runtime = AppRuntime(
      services: _services(),
      destructiveOperationGate: SerialDestructiveOperationGate(),
      clearAllData: () async {},
      dispose: () async => throw StateError('unmount dispose failed'),
    );
    await tester.pumpWidget(
      BabyTimelineBootstrap(
        bootstrap: () async => BootstrapResult.ready(runtime),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing a ready bootstrap releases the previous runtime', (
    tester,
  ) async {
    var disposeCount = 0;
    final runtime = AppRuntime(
      services: _services(),
      destructiveOperationGate: SerialDestructiveOperationGate(),
      clearAllData: () async {},
      dispose: () async => disposeCount += 1,
    );
    await tester.pumpWidget(
      BabyTimelineBootstrap(
        key: const ValueKey('bootstrap'),
        bootstrap: () async => BootstrapResult.ready(runtime),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      BabyTimelineBootstrap(
        key: const ValueKey('bootstrap'),
        bootstrap: () async => BootstrapResult.failed(
          StateError('replacement failed'),
          StackTrace.current,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(disposeCount, 1);
  });

  testWidgets('throwing replacement dispose does not block the new result', (
    tester,
  ) async {
    final previousRuntime = AppRuntime(
      services: _services(),
      destructiveOperationGate: SerialDestructiveOperationGate(),
      clearAllData: () async {},
      dispose: () async => throw StateError('replacement dispose failed'),
    );
    final replacementBaby = Baby(
      id: 'replacement-baby',
      name: '新宝宝',
      birthDate: '2025-06-12',
      createdAt: DateTime.utc(2025, 6, 12),
      updatedAt: DateTime.utc(2025, 6, 12),
    );
    var replacementAttempts = 0;
    await tester.pumpWidget(
      BabyTimelineBootstrap(
        key: const ValueKey('bootstrap'),
        bootstrap: () async => BootstrapResult.ready(previousRuntime),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      BabyTimelineBootstrap(
        key: const ValueKey('bootstrap'),
        bootstrap: () async {
          replacementAttempts += 1;
          return BootstrapResult.ready(
            AppRuntime(
              services: _services(baby: replacementBaby),
              destructiveOperationGate: SerialDestructiveOperationGate(),
              clearAllData: () async {},
              dispose: () async {},
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(replacementAttempts, 1);
    expect(find.text('新宝宝'), findsOneWidget);
  });

  test('AppRuntime dispose is concurrent-safe and best-effort', () async {
    final releaseDispose = Completer<void>();
    var disposeCount = 0;
    final runtime = AppRuntime(
      services: _services(),
      destructiveOperationGate: SerialDestructiveOperationGate(),
      clearAllData: () async {},
      dispose: () async {
        disposeCount += 1;
        await releaseDispose.future;
        throw StateError('runtime dispose failed');
      },
    );

    final first = runtime.dispose();
    final second = runtime.dispose();
    expect(identical(first, second), isTrue);
    expect(disposeCount, 1);

    releaseDispose.complete();
    await Future.wait([first, second]);
    await runtime.dispose();

    expect(disposeCount, 1);
  });

  testWidgets('ready bootstrap injects repositories and backup into routes', (
    tester,
  ) async {
    final baby = Baby(
      id: 'baby-1',
      name: '安安',
      birthDate: '2025-06-12',
      createdAt: DateTime.utc(2025, 6, 12),
      updatedAt: DateTime.utc(2025, 6, 12),
    );
    final services = _services(baby: baby);

    await tester.pumpWidget(
      BabyTimelineBootstrap(
        bootstrap: () async => BootstrapResult.ready(
          AppRuntime(
            services: services,
            destructiveOperationGate: SerialDestructiveOperationGate(),
            clearAllData: () async {},
            dispose: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('安安'), findsOneWidget);
    await tester.tap(find.text('宝宝'));
    await tester.pumpAndSettle();
    expect(find.text('导出备份'), findsOneWidget);
    expect(find.text('恢复备份'), findsOneWidget);
  });

  testWidgets('production ready shell reads every service provider', (
    tester,
  ) async {
    final observer = _ProviderReadObserver();
    final baby = Baby(
      id: 'baby-provider',
      name: 'Provider 宝宝',
      birthDate: '2025-06-12',
      createdAt: DateTime.utc(2025, 6, 12),
      updatedAt: DateTime.utc(2025, 6, 12),
    );
    final runtime = AppRuntime(
      services: _services(baby: baby),
      destructiveOperationGate: SerialDestructiveOperationGate(),
      clearAllData: () async {},
      dispose: () async {},
    );

    await tester.pumpWidget(
      ProviderScope(
        observers: [observer],
        child: BabyTimelineBootstrap(
          bootstrap: () async => BootstrapResult.ready(runtime),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Provider 宝宝'), findsOneWidget);
    expect(
      observer.added,
      containsAll(<ProviderBase<Object?>>[
        databaseProvider,
        babyRepositoryProvider,
        recordRepositoryProvider,
        mediaServiceProvider,
        backupServiceProvider,
      ]),
    );
  });

  testWidgets('stable non-SQLite runtime still exposes clear-all', (
    tester,
  ) async {
    final baby = Baby(
      id: 'baby-1',
      name: '安安',
      birthDate: '2025-06-12',
      createdAt: DateTime.utc(2025, 6, 12),
      updatedAt: DateTime.utc(2025, 6, 12),
    );
    var clearCount = 0;
    final runtime = AppRuntime(
      services: _services(baby: baby),
      destructiveOperationGate: SerialDestructiveOperationGate(),
      clearAllData: () async => clearCount += 1,
      dispose: () async {},
    );
    await tester.pumpWidget(
      BabyTimelineBootstrap(
        bootstrap: () async => BootstrapResult.ready(runtime),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('宝宝'));
    await tester.pumpAndSettle();

    expect(find.text('清空所有数据'), findsOneWidget);
    await tester.tap(find.text('清空所有数据'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('clear-baby-name')), '安安');
    await tester.pump();
    await tester.tap(find.text('确认清空'));
    await tester.pumpAndSettle();

    expect(clearCount, 1);
  });

  test(
    'framework error logger writes only to the configured local file',
    () async {
      final root = await Directory.systemTemp.createTemp('bootstrap-log-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final logger = LocalDebugLogger(
        applicationSupportDirectory: () async => root,
        now: () => DateTime.utc(2026, 8, 1, 12),
      );

      await logger.write(
        'flutter framework',
        StateError('render failed'),
        StackTrace.fromString('frame #0'),
      );

      final log = File(p.join(root.path, 'debug', 'app.log'));
      expect(await log.readAsString(), contains('[flutter framework]'));
      expect(await log.readAsString(), contains('render failed'));
      expect(
        await root
            .list(recursive: true)
            .where((entity) => entity is File)
            .length,
        1,
      );
    },
  );
}

class _RecordingEnvironment implements BootstrapEnvironment {
  _RecordingEnvironment({
    this.failAt,
    this.rollbackDetected = false,
    this.disposeError,
  }) : appServices = _services();

  final String? failAt;
  final bool rollbackDetected;
  final Object? disposeError;
  final List<String> events = [];
  final AppServices appServices;

  void _record(String event) {
    events.add(event);
    if (failAt == event || event.startsWith('$failAt:')) {
      throw StateError('$event failed');
    }
  }

  @override
  Future<void> ensureDirectories() async =>
      _record('directories.ensureCreated');

  @override
  Future<void> recoverLegacyRollback() async {
    _record('rollback.recover');
    if (rollbackDetected) _record('rollback.restore');
  }

  @override
  Future<void> openDatabase() async => _record('database.open');

  @override
  Future<void> migrateDatabase() async => _record('database.migrate');

  @override
  AppServices buildServices(DestructiveOperationGate gate) {
    _record('services.build');
    return appServices;
  }

  @override
  Future<void> clearAllData(
    AppServices services,
    DestructiveOperationGate gate,
  ) async {}

  @override
  Future<void> removeStagingFiles() async =>
      _record('media.removeStagingFiles');

  @override
  Future<Set<String>> referencedMediaPaths(AppServices services) async {
    _record('media.referencedPaths');
    return {'/media/referenced.jpg'};
  }

  @override
  Future<void> removeOrphans(
    AppServices services,
    Set<String> referencedPaths,
  ) async => _record('media.removeOrphans:${referencedPaths.single}');

  @override
  Future<void> removeExpiredExports(
    AppServices services,
    Duration maxAge,
  ) async => _record('backup.removeExpiredExports:${maxAge.inHours}');

  @override
  Future<void> logDebugError(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) async => _record('debug:$operation');

  @override
  Future<void> dispose() async {
    _record('environment.dispose');
    final error = disposeError;
    if (error != null) throw error;
  }
}

class _ProviderReadObserver extends ProviderObserver {
  final added = <ProviderBase<Object?>>[];

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    added.add(provider);
  }
}

class _SerialEnvironment implements BootstrapEnvironment {
  final events = <String>[];
  final restoreStarted = Completer<void>();
  final releaseRestore = Completer<void>();
  late _GateBackup backup;

  @override
  AppServices buildServices(DestructiveOperationGate gate) {
    backup = _GateBackup(
      gate,
      events: events,
      started: restoreStarted,
      release: releaseRestore,
    );
    return AppServices(
      database: _Database(),
      babies: _Babies(),
      records: _Records(),
      media: _Media(),
      backup: backup,
    );
  }

  @override
  Future<void> clearAllData(
    AppServices services,
    DestructiveOperationGate gate,
  ) => gate.run(() async {
    events.add('clear.start');
    events.add('clear.end');
  });

  @override
  Future<void> dispose() async {}

  @override
  Future<void> ensureDirectories() async {}

  @override
  Future<void> logDebugError(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) async {}

  @override
  Future<void> migrateDatabase() async {}

  @override
  Future<void> openDatabase() async {}

  @override
  Future<void> recoverLegacyRollback() async {}

  @override
  Future<void> removeExpiredExports(
    AppServices services,
    Duration maxAge,
  ) async {}

  @override
  Future<void> removeOrphans(
    AppServices services,
    Set<String> referencedPaths,
  ) async {}

  @override
  Future<void> removeStagingFiles() async {}

  @override
  Future<Set<String>> referencedMediaPaths(AppServices services) async => {};
}

AppServices _services({Baby? baby}) => AppServices(
  database: _Database(),
  babies: _Babies(baby),
  records: _Records(),
  media: _Media(),
  backup: _Backup(),
);

class _Database implements DatabaseLifecycle {
  @override
  Future<void> reopen() async {}

  @override
  Future<T> withClosedDatabase<T>(
    Future<T> Function(String databasePath) work,
  ) => work('/database/app.sqlite');
}

class _Babies implements BabyRepository {
  _Babies([this.baby]);

  final Baby? baby;

  @override
  Future<Baby> create(BabyDraft draft) => throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();

  @override
  Future<Baby?> get(String id) async => null;

  @override
  Future<Baby?> getCurrent() async => baby;

  @override
  Future<Baby> update(String id, BabyDraft draft) => throw UnimplementedError();
}

class _Records implements RecordRepository {
  @override
  Future<TimelineRecord> create(NewRecordInput input) =>
      throw UnimplementedError();

  @override
  Future<List<Attachment>> delete(String id) => throw UnimplementedError();

  @override
  Future<TimelineRecord?> get(String id) async => null;

  @override
  Future<T> inTransaction<T>(
    Future<T> Function(RecordTransaction transaction) work,
  ) => throw UnimplementedError();

  @override
  Future<List<TimelineRecord>> list({Set<RecordType> types = const {}}) async =>
      const [];

  @override
  Future<TimelineRecord> update(String id, NewRecordInput input) =>
      throw UnimplementedError();
}

class _Media implements MediaService {
  @override
  Future<CommittedMedia> commit(StagedMedia staged) =>
      throw UnimplementedError();

  @override
  Future<void> remove(Iterable<String> paths) async {}

  @override
  Future<void> removeOrphans(Set<String> referencedPaths) async {}

  @override
  Future<void> rollback(StagedMedia staged) async {}

  @override
  Future<StagedMedia> stage(PickedMedia input) => throw UnimplementedError();
}

class _Backup implements BackupService {
  @override
  Future<String> exportBackup() => throw UnimplementedError();

  @override
  Future<BackupInspection> inspect(String archivePath) =>
      throw UnimplementedError();

  @override
  Future<void> removeExpiredExports(Duration maxAge) async {}

  @override
  Future<void> restore(BackupInspection inspected) =>
      throw UnimplementedError();
}

class _GateBackup extends _Backup {
  _GateBackup(
    this.gate, {
    required this.events,
    required this.started,
    required this.release,
  });

  final DestructiveOperationGate gate;
  final List<String> events;
  final Completer<void> started;
  final Completer<void> release;

  Future<void> runRestore() => gate.run(() async {
    events.add('restore.start');
    started.complete();
    await release.future;
    events.add('restore.end');
  });
}
