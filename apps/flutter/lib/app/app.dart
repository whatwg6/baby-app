import 'dart:async';

import 'package:baby_growth_timeline/core/theme/app_theme.dart';
import 'package:baby_growth_timeline/features/baby/application/baby_controller.dart';
import 'package:baby_growth_timeline/features/timeline/application/timeline_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'bootstrap.dart';
import 'bootstrap_error_page.dart';
import 'providers.dart';
import 'router.dart';

class BabyTimelineApp extends StatelessWidget {
  const BabyTimelineApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '宝宝成长记',
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}

class BabyTimelineBootstrap extends StatefulWidget {
  const BabyTimelineBootstrap({super.key, required this.bootstrap});

  final Future<BootstrapResult> Function() bootstrap;

  @override
  State<BabyTimelineBootstrap> createState() => _BabyTimelineBootstrapState();
}

class _BabyTimelineBootstrapState extends State<BabyTimelineBootstrap> {
  BootstrapResult? _result;
  var _attempt = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant BabyTimelineBootstrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bootstrap != widget.bootstrap) _start();
  }

  Future<void> _start() async {
    final attempt = ++_attempt;
    final bootstrap = widget.bootstrap;
    final previousResult = _result;
    setState(() => _result = null);
    late final BootstrapResult result;
    try {
      await previousResult?.dispose();
      if (!mounted || attempt != _attempt) return;
      result = await bootstrap();
    } catch (error, stackTrace) {
      result = BootstrapResult.failed(error, stackTrace);
    }
    if (!mounted || attempt != _attempt) {
      await result.dispose();
      return;
    }
    setState(() => _result = result);
  }

  @override
  void dispose() {
    unawaited(_result?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result == null) {
      return const _BootstrapMaterialApp(home: _BrandStartupPage());
    }
    final services = result.services;
    if (services == null) {
      return _BootstrapMaterialApp(home: BootstrapErrorPage(onRetry: _start));
    }
    return ProviderScope(
      overrides: [appRuntimeProvider.overrideWithValue(result.runtime!)],
      child: BabyTimelineReadyApp(key: ValueKey(result.runtime)),
    );
  }
}

class BabyTimelineReadyApp extends ConsumerStatefulWidget {
  const BabyTimelineReadyApp({super.key});

  @override
  ConsumerState<BabyTimelineReadyApp> createState() =>
      _BabyTimelineReadyAppState();
}

class _BabyTimelineReadyAppState extends ConsumerState<BabyTimelineReadyApp> {
  late final BabyController _babyController;
  late final TimelineController _timelineController;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    final services = AppServices(
      database: ref.read(databaseProvider),
      babies: ref.read(babyRepositoryProvider),
      records: ref.read(recordRepositoryProvider),
      media: ref.read(mediaServiceProvider),
      backup: ref.read(backupServiceProvider),
    );
    _babyController = BabyController(services.babies);
    _timelineController = TimelineController(services.records);
    _router = createRouter(
      babyController: _babyController,
      recordRepository: services.records,
      timelineController: _timelineController,
      services: services,
      clearAllData: runtime.clearAllData,
      destructiveOperationGate: runtime.destructiveOperationGate,
    );
  }

  @override
  void dispose() {
    _router.dispose();
    _babyController.dispose();
    _timelineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BabyTimelineApp(router: _router);
}

class _BootstrapMaterialApp extends StatelessWidget {
  const _BootstrapMaterialApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) =>
      MaterialApp(title: '宝宝成长记', theme: AppTheme.light, home: home);
}

class _BrandStartupPage extends StatelessWidget {
  const _BrandStartupPage();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.child_care, size: 64),
            SizedBox(height: 16),
            Text('宝宝成长记'),
            SizedBox(height: 12),
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在打开本地数据…'),
          ],
        ),
      ),
    ),
  );
}
