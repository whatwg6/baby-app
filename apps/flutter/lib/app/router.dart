import 'package:baby_growth_timeline/features/baby/application/baby_controller.dart';
import 'package:baby_growth_timeline/features/baby/presentation/baby_page.dart';
import 'package:baby_growth_timeline/features/baby/presentation/baby_setup_page.dart';
import 'package:baby_growth_timeline/data/repositories/record_repository.dart';
import 'package:baby_growth_timeline/domain/destructive_operation_gate.dart';
import 'package:baby_growth_timeline/features/records/presentation/add_record_page.dart';
import 'package:baby_growth_timeline/features/records/presentation/record_detail_page.dart';
import 'package:baby_growth_timeline/features/records/presentation/record_editor_page.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';
import 'package:baby_growth_timeline/features/timeline/application/timeline_controller.dart';
import 'package:baby_growth_timeline/features/timeline/presentation/timeline_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';

GoRouter createRouter({
  bool hasBaby = false,
  BabyController? babyController,
  RecordRepository? recordRepository,
  TimelineController? timelineController,
  AppServices? services,
  Future<void> Function()? clearAllData,
  DestructiveOperationGate? destructiveOperationGate,
}) {
  final resolvedBabyController =
      babyController ??
      (services == null ? null : BabyController(services.babies));
  final resolvedRecordRepository = recordRepository ?? services?.records;
  final resolvedTimelineController =
      timelineController ??
      (resolvedRecordRepository == null
          ? null
          : TimelineController(resolvedRecordRepository));
  final addBranchReset = _AddBranchResetSignal();
  return GoRouter(
    initialLocation: '/timeline',
    redirect: (context, state) async {
      if (resolvedBabyController == null) {
        return null;
      }
      await resolvedBabyController.load();
      final hasStoredBaby = resolvedBabyController.baby != null;
      final isSetupRoute = state.matchedLocation == '/baby/setup';
      if (!hasStoredBaby && !isSetupRoute) {
        return '/baby/setup';
      }
      if (hasStoredBaby && isSetupRoute) {
        return '/baby';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/timeline'),
      GoRoute(
        path: '/records/:id',
        builder: (context, state) => RecordDetailPage(
          recordId: state.pathParameters['id']!,
          repository: resolvedRecordRepository,
          mediaService: services?.media,
          destructiveOperationGate: destructiveOperationGate,
          queueOrphanCleanup: services == null ? null : (_) async {},
          timelineController: resolvedTimelineController,
        ),
      ),
      GoRoute(
        path: '/records/:id/edit',
        builder: (context, state) {
          if (resolvedRecordRepository == null) {
            return const _ProfileUnavailablePage();
          }
          final type = _recordType(state.uri.queryParameters['type']);
          return RecordEditorPage(
            type: type ?? RecordType.moment,
            recordId: state.pathParameters['id']!,
            repository: resolvedRecordRepository,
            mediaService: services?.media,
          );
        },
      ),
      GoRoute(
        path: '/baby/setup',
        builder: (context, state) => resolvedBabyController == null
            ? const _ProfileUnavailablePage()
            : BabySetupPage(controller: resolvedBabyController),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return _AppShell(
            navigationShell: navigationShell,
            addBranchReset: addBranchReset,
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/timeline',
                builder: (context, state) => TimelinePage(
                  hasBaby: hasBaby || resolvedBabyController?.baby != null,
                  controller: resolvedTimelineController,
                  babyController: resolvedBabyController,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/add',
                builder: (context, state) => const AddRecordPage(),
              ),
              GoRoute(
                path: '/add/:type',
                builder: (context, state) {
                  final type = _recordType(state.pathParameters['type']);
                  return type == null || resolvedRecordRepository == null
                      ? const _ProfileUnavailablePage()
                      : RecordEditorPage(
                          type: type,
                          repository: resolvedRecordRepository,
                          mediaService: services?.media,
                          onSaved: () async {
                            final router = GoRouter.of(context);
                            addBranchReset.arm();
                            router.go('/timeline');
                            await resolvedTimelineController?.reload();
                          },
                        );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/baby',
                builder: (context, state) => BabyPage(
                  controller: resolvedBabyController,
                  backupService: services?.backup,
                  onBackupRestored: () async {
                    await Future.wait([
                      resolvedBabyController?.reload() ?? Future<void>.value(),
                      resolvedTimelineController?.reload() ??
                          Future<void>.value(),
                    ]);
                  },
                  onClearAllData: clearAllData == null
                      ? null
                      : () async {
                          await clearAllData();
                          await Future.wait([
                            resolvedBabyController?.reload() ??
                                Future<void>.value(),
                            resolvedTimelineController?.reload() ??
                                Future<void>.value(),
                          ]);
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

RecordType? _recordType(String? value) {
  if (value == null) return null;
  for (final type in RecordType.values) {
    if (type.name == value) return type;
  }
  return null;
}

class _ProfileUnavailablePage extends StatelessWidget {
  const _ProfileUnavailablePage();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('宝宝资料暂不可用')));
}

class _AppShell extends StatelessWidget {
  const _AppShell({
    required this.navigationShell,
    required this.addBranchReset,
  });

  final StatefulNavigationShell navigationShell;
  final _AddBranchResetSignal addBranchReset;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          final resetAddBranch = index == 1 && addBranchReset.consume();
          navigationShell.goBranch(
            index,
            initialLocation:
                resetAddBranch || index == navigationShell.currentIndex,
          );
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.timeline_outlined),
            selectedIcon: Icon(Icons.timeline),
            label: '时间轴',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline, color: colorScheme.primary),
            selectedIcon: Icon(Icons.add_circle, color: colorScheme.primary),
            label: '添加',
          ),
          const NavigationDestination(
            icon: Icon(Icons.child_care_outlined),
            selectedIcon: Icon(Icons.child_care),
            label: '宝宝',
          ),
        ],
      ),
    );
  }
}

class _AddBranchResetSignal {
  var _pending = false;

  void arm() => _pending = true;

  bool consume() {
    if (!_pending) return false;
    _pending = false;
    return true;
  }
}
