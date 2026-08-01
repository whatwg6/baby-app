import 'dart:async';

import 'package:baby_growth_timeline/app/app.dart';
import 'package:baby_growth_timeline/app/router.dart';
import 'package:baby_growth_timeline/data/repositories/baby_repository.dart';
import 'package:baby_growth_timeline/domain/models/baby.dart';
import 'package:baby_growth_timeline/features/baby/application/baby_controller.dart';
import 'package:baby_growth_timeline/features/baby/presentation/baby_header.dart';
import 'package:baby_growth_timeline/features/baby/presentation/baby_page.dart';
import 'package:baby_growth_timeline/features/baby/presentation/baby_setup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final baby = Baby(
    id: 'baby-1',
    name: '安安',
    birthDate: '2025-06-15',
    createdAt: DateTime.utc(2025, 6, 15),
    updatedAt: DateTime.utc(2025, 6, 15),
  );

  testWidgets('shows a placeholder, name, and calendar age', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BabyHeader(baby: baby, now: () => DateTime(2026, 7, 15)),
      ),
    );

    expect(find.byIcon(Icons.child_care), findsOneWidget);
    expect(find.text('安安'), findsOneWidget);
    expect(find.text('1岁1个月'), findsOneWidget);
  });

  testWidgets('refreshes the age label from the injected clock', (
    tester,
  ) async {
    var now = DateTime(2026, 7, 14);
    Widget buildHeader() => MaterialApp(
      home: BabyHeader(baby: baby, now: () => now),
    );

    await tester.pumpWidget(buildHeader());
    expect(find.text('1岁0个月'), findsOneWidget);

    now = DateTime(2026, 7, 15);
    await tester.pumpWidget(buildHeader());
    expect(find.text('1岁1个月'), findsOneWidget);
  });

  testWidgets('redirects an existing baby away from profile setup', (
    tester,
  ) async {
    final controller = BabyController(_ExistingBabyRepository(baby));
    final router = createRouter(babyController: controller);
    addTearDown(router.dispose);
    await tester.pumpWidget(BabyTimelineApp(router: router));
    await tester.pumpAndSettle();

    router.go('/baby/setup');
    await tester.pumpAndSettle();

    expect(find.text('编辑资料'), findsOneWidget);
    expect(find.text('添加宝宝资料'), findsNothing);
  });

  testWidgets('keeps an edit form usable when its save fails', (tester) async {
    final repository = _DelayedUpdateBabyRepository(baby);
    final controller = BabyController(repository);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BabyPage(controller: controller)),
      ),
    );

    await tester.tap(find.text('编辑资料'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('baby-name')), '安安新名');
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.byKey(const Key('baby-name')), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    repository.updateCompleter.completeError(StateError('save failed'));
    await tester.pump();
    await tester.pump();

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('baby-name')))
          .controller!
          .text,
      '安安新名',
    );
    expect(find.text('保存失败，请稍后重试。'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('keeps setup fields visible when its save fails', (tester) async {
    final controller = BabyController(_FailingCreateBabyRepository());
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(home: BabySetupPage(controller: controller)),
    );

    await tester.enterText(find.byKey(const Key('baby-name')), '安安');
    await tester.enterText(find.byKey(const Key('birth-date')), '2025-06-15');
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump();

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('baby-name')))
          .controller!
          .text,
      '安安',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('birth-date')))
          .controller!
          .text,
      '2025-06-15',
    );
    expect(find.text('保存失败，请稍后重试。'), findsOneWidget);
  });
}

class _ExistingBabyRepository implements BabyRepository {
  _ExistingBabyRepository(this.baby);

  final Baby baby;

  @override
  Future<Baby> create(BabyDraft draft) async =>
      throw UnsupportedError('create');

  @override
  Future<void> delete(String id) async => throw UnsupportedError('delete');

  @override
  Future<Baby?> get(String id) async => id == baby.id ? baby : null;

  @override
  Future<Baby?> getCurrent() async => baby;

  @override
  Future<Baby> update(String id, BabyDraft draft) async =>
      throw UnsupportedError('update');
}

class _DelayedUpdateBabyRepository extends _ExistingBabyRepository {
  _DelayedUpdateBabyRepository(super.baby);

  final updateCompleter = Completer<Baby>();

  @override
  Future<Baby> update(String id, BabyDraft draft) => updateCompleter.future;
}

class _FailingCreateBabyRepository implements BabyRepository {
  @override
  Future<Baby> create(BabyDraft draft) async => throw StateError('save failed');

  @override
  Future<void> delete(String id) async => throw UnsupportedError('delete');

  @override
  Future<Baby?> get(String id) async => null;

  @override
  Future<Baby?> getCurrent() async => null;

  @override
  Future<Baby> update(String id, BabyDraft draft) async =>
      throw UnsupportedError('update');
}
