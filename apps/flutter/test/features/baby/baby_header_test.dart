import 'dart:async';
import 'dart:io';

import 'package:baby_growth_timeline/app/app.dart';
import 'package:baby_growth_timeline/app/router.dart';
import 'package:baby_growth_timeline/data/repositories/baby_repository.dart';
import 'package:baby_growth_timeline/data/repositories/record_repository.dart';
import 'package:baby_growth_timeline/domain/models/attachment.dart';
import 'package:baby_growth_timeline/domain/models/baby.dart';
import 'package:baby_growth_timeline/domain/models/record_draft.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';
import 'package:baby_growth_timeline/features/baby/application/baby_controller.dart';
import 'package:baby_growth_timeline/features/baby/presentation/baby_header.dart';
import 'package:baby_growth_timeline/features/baby/presentation/baby_page.dart';
import 'package:baby_growth_timeline/features/baby/presentation/baby_setup_page.dart';
import 'package:baby_growth_timeline/features/timeline/application/timeline_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/media_fixture.dart';

void main() {
  late Directory mediaDirectory;

  setUp(() {
    mediaDirectory = Directory.systemTemp.createTempSync('baby-header-media-');
  });

  tearDown(() {
    if (mediaDirectory.existsSync()) {
      mediaDirectory.deleteSync(recursive: true);
    }
  });

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

  testWidgets('renders an existing private avatar file', (tester) async {
    final avatar = writeValidPng(mediaDirectory, 'avatar.png');

    await tester.pumpWidget(
      MaterialApp(
        home: BabyHeader(
          baby: baby.copyWith(avatarPath: avatar.path),
          now: () => DateTime(2026, 7, 15),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.child_care), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses a safe avatar placeholder for a missing file', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BabyHeader(
          baby: baby.copyWith(avatarPath: '${mediaDirectory.path}/missing.png'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.child_care), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses a safe avatar placeholder when image decoding fails', (
    tester,
  ) async {
    final corrupt = File('${mediaDirectory.path}/corrupt.png');
    corrupt.writeAsStringSync('not an image');
    await tester.pumpWidget(
      MaterialApp(
        home: BabyHeader(baby: baby.copyWith(avatarPath: corrupt.path)),
      ),
    );
    await pumpUntilVisible(tester, find.byIcon(Icons.child_care));

    expect(find.byIcon(Icons.child_care), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('timeline header follows a saved profile in the cached branch', (
    tester,
  ) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final birthDate = _dateOnly(yesterday);
    final repository = _MutableBabyRepository(baby);
    final controller = BabyController(repository);
    final router = createRouter(
      babyController: controller,
      timelineController: TimelineController(_EmptyRecordRepository()),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(BabyTimelineApp(router: router));
    await tester.pumpAndSettle();

    expect(find.text('安安'), findsOneWidget);
    await tester.tap(find.text('宝宝'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑资料'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('baby-name')), '果果');
    await tester.enterText(find.byKey(const Key('birth-date')), birthDate);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('时间轴'));
    await tester.pumpAndSettle();

    expect(find.text('果果'), findsOneWidget);
    expect(find.text('1天'), findsOneWidget);
    expect(find.text('安安'), findsNothing);
  });

  testWidgets(
    'timeline header follows a restore reload without rebuilding app',
    (tester) async {
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      final repository = _MutableBabyRepository(baby);
      final controller = BabyController(repository);
      final router = createRouter(
        babyController: controller,
        timelineController: TimelineController(_EmptyRecordRepository()),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(BabyTimelineApp(router: router));
      await tester.pumpAndSettle();
      expect(find.text('安安'), findsOneWidget);

      repository.baby = baby.copyWith(
        name: '恢复后的宝宝',
        birthDate: _dateOnly(twoDaysAgo),
      );
      await controller.reload();
      await tester.pump();

      expect(find.text('恢复后的宝宝'), findsOneWidget);
      expect(find.text('2天'), findsOneWidget);
      expect(find.text('安安'), findsNothing);
    },
  );

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

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

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

class _MutableBabyRepository implements BabyRepository {
  _MutableBabyRepository(this.baby);

  Baby baby;

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
  Future<Baby> update(String id, BabyDraft draft) async {
    baby = baby.copyWith(
      name: draft.name,
      birthDate: draft.birthDate,
      sex: draft.sex,
      avatarPath: draft.avatarPath,
      updatedAt: DateTime.now().toUtc(),
    );
    return baby;
  }
}

class _EmptyRecordRepository implements RecordRepository {
  @override
  Future<TimelineRecord> create(NewRecordInput input) =>
      throw UnsupportedError('create');

  @override
  Future<List<Attachment>> delete(String id) =>
      throw UnsupportedError('delete');

  @override
  Future<TimelineRecord?> get(String id) async => null;

  @override
  Future<T> inTransaction<T>(Future<T> Function(RecordTransaction) work) =>
      throw UnsupportedError('inTransaction');

  @override
  Future<List<TimelineRecord>> list({Set<RecordType> types = const {}}) async =>
      const [];

  @override
  Future<TimelineRecord> update(String id, NewRecordInput input) =>
      throw UnsupportedError('update');
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
