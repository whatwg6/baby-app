import 'dart:async';

import 'package:baby_growth_timeline/data/repositories/record_repository.dart';
import 'package:baby_growth_timeline/domain/models/attachment.dart';
import 'package:baby_growth_timeline/domain/models/record_draft.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';
import 'package:baby_growth_timeline/features/media/domain/media_service.dart';
import 'package:baby_growth_timeline/features/records/application/record_editor_controller.dart';
import 'package:baby_growth_timeline/features/records/presentation/record_editor_page.dart';
import 'package:baby_growth_timeline/features/records/presentation/record_type_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  final now = DateTime(2026, 8, 1, 9, 30);

  Future<void> pumpEditor(
    WidgetTester tester, {
    required RecordType type,
    String? recordId,
    required _EditorRepository repository,
    Future<void> Function()? onSaved,
  }) async {
    final controller = RecordEditorController(
      repository,
      type: type,
      recordId: recordId,
      now: () => now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RecordEditorPage(
          type: type,
          recordId: recordId,
          controller: controller,
          onSaved: onSaved ?? () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    final save = find.text('保存');
    await tester.ensureVisible(save);
    await tester.tap(save);
  }

  testWidgets('picker offers exactly the four record types', (tester) async {
    final selected = <RecordType>[];
    await tester.pumpWidget(
      MaterialApp(home: RecordTypePicker(onSelected: selected.add)),
    );

    await tester.tap(find.text('珍贵时刻'));
    await tester.tap(find.text('成长数据'));
    await tester.tap(find.text('日常活动'));
    await tester.tap(find.text('里程碑'));

    expect(selected, RecordType.values);
  });

  testWidgets('reinitializes the editor when widget parameters change', (
    tester,
  ) async {
    final repository = _EditorRepository();
    Widget editor(RecordType type) => MaterialApp(
      home: RecordEditorPage(
        type: type,
        repository: repository,
        now: () => now,
        onSaved: () async {},
      ),
    );

    await tester.pumpWidget(editor(RecordType.growth));
    await tester.enterText(find.byKey(const Key('growth-height')), '68.5');
    await tester.pumpWidget(editor(RecordType.milestone));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('milestone-title')), findsOneWidget);
    expect(find.byKey(const Key('growth-height')), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('milestone-title')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('ignores an old save completion after parameters change', (
    tester,
  ) async {
    final oldSave = Completer<TimelineRecord>();
    final oldRepository = _EditorRepository(createFuture: oldSave.future);
    final newRepository = _EditorRepository();
    var postSaveCalls = 0;
    Widget editor(RecordType type, _EditorRepository repository) => MaterialApp(
      home: RecordEditorPage(
        type: type,
        repository: repository,
        now: () => now,
        onSaved: () async => postSaveCalls += 1,
      ),
    );

    await tester.pumpWidget(editor(RecordType.milestone, oldRepository));
    await tester.enterText(find.byKey(const Key('milestone-title')), '旧编辑器');
    await tapSave(tester);
    await tester.pump();
    await tester.pumpWidget(editor(RecordType.growth, newRepository));
    await tester.pump();

    oldSave.complete(_savedRecord(RecordType.milestone));
    await tester.pump();

    expect(find.byKey(const Key('growth-height')), findsOneWidget);
    expect(find.text('已保存'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(postSaveCalls, 0);
  });

  testWidgets('empty moment cannot be saved', (tester) async {
    final repository = _EditorRepository();
    await pumpEditor(tester, type: RecordType.moment, repository: repository);

    await tapSave(tester);
    await tester.pump();

    expect(find.text('珍贵时刻请填写文字或添加媒体。'), findsOneWidget);
    expect(repository.createInput, isNull);
  });

  testWidgets('growth accepts one valid value and rejects a negative value', (
    tester,
  ) async {
    final repository = _EditorRepository();
    await pumpEditor(tester, type: RecordType.growth, repository: repository);

    final height = find.byKey(const Key('growth-height'));
    expect(tester.widget<TextFormField>(height).enabled, isTrue);
    await tester.tap(height);
    await tester.enterText(height, '68.5');
    await tester.pump();
    await tapSave(tester);
    await tester.pumpAndSettle();
    expect(
      repository.createInput?.details,
      const RecordDetails.growth(heightCm: 68.5),
    );

    await pumpEditor(
      tester,
      type: RecordType.growth,
      repository: _EditorRepository(),
    );
    await tester.enterText(find.byKey(const Key('growth-height')), '-1');
    await tapSave(tester);
    await tester.pump();
    expect(find.text('身高请填写 20–250 cm 之间的数值。'), findsOneWidget);
  });

  testWidgets('growth rejects malformed text alongside another valid value', (
    tester,
  ) async {
    final repository = _EditorRepository();
    await pumpEditor(tester, type: RecordType.growth, repository: repository);

    await tester.enterText(
      find.byKey(const Key('growth-height')),
      'not-a-number',
    );
    await tester.enterText(find.byKey(const Key('growth-weight')), '7.2');
    await tapSave(tester);
    await tester.pump();

    expect(find.text('身高请填写 20–250 cm 之间的数值。'), findsOneWidget);
    expect(repository.createInput, isNull);
  });

  testWidgets('activity requires a type and rejects zero minutes', (
    tester,
  ) async {
    final repository = _EditorRepository();
    await pumpEditor(tester, type: RecordType.activity, repository: repository);

    await tapSave(tester);
    await tester.pump();
    expect(find.text('请选择活动类型。'), findsOneWidget);

    final activityType = find.byType(DropdownButton<ActivityType>);
    await tester.ensureVisible(activityType);
    await tester.tap(activityType);
    await tester.pumpAndSettle();
    await tester.tap(find.text('睡眠').last);
    await tester.enterText(find.byKey(const Key('activity-duration')), '0');
    await tapSave(tester);
    await tester.pump();
    expect(find.text('时长请填写 1–1440 分钟。'), findsOneWidget);
  });

  testWidgets('activity retains values when another field changes', (
    tester,
  ) async {
    final repository = _EditorRepository();
    await pumpEditor(tester, type: RecordType.activity, repository: repository);

    await tester.tap(find.byKey(const Key('activity-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('睡眠').last);
    await tester.enterText(find.byKey(const Key('activity-amount')), '120');
    await tester.enterText(find.byKey(const Key('activity-duration')), '15');
    await tapSave(tester);
    await tester.pumpAndSettle();

    expect(
      repository.createInput?.details,
      const RecordDetails.activity(
        activityType: ActivityType.sleep,
        amount: 120,
        durationMinutes: 15,
      ),
    );
  });

  testWidgets('activity rejects malformed amount text', (tester) async {
    final repository = _EditorRepository();
    await pumpEditor(tester, type: RecordType.activity, repository: repository);

    await tester.tap(find.byKey(const Key('activity-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('喂养').last);
    await tester.enterText(
      find.byKey(const Key('activity-amount')),
      'not-a-number',
    );
    await tapSave(tester);
    await tester.pump();

    expect(find.text('数量请填写大于 0 的数值。'), findsOneWidget);
    expect(repository.createInput, isNull);
  });

  testWidgets('activity rejects malformed duration text', (tester) async {
    final repository = _EditorRepository();
    await pumpEditor(tester, type: RecordType.activity, repository: repository);

    await tester.tap(find.byKey(const Key('activity-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('睡眠').last);
    await tester.enterText(
      find.byKey(const Key('activity-duration')),
      'not-a-number',
    );
    await tapSave(tester);
    await tester.pump();

    expect(find.text('时长请填写 1–1440 分钟。'), findsOneWidget);
    expect(repository.createInput, isNull);
  });

  testWidgets('milestone requires a title', (tester) async {
    final repository = _EditorRepository();
    await pumpEditor(
      tester,
      type: RecordType.milestone,
      repository: repository,
    );

    await tapSave(tester);
    await tester.pump();

    expect(find.text('请输入里程碑标题。'), findsOneWidget);
  });

  testWidgets('uses injected current time and allows occurrence time changes', (
    tester,
  ) async {
    final repository = _EditorRepository();
    await pumpEditor(
      tester,
      type: RecordType.milestone,
      repository: repository,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('occurred-at')))
          .controller!
          .text,
      '2026-08-01 09:30',
    );

    await tester.enterText(
      find.byKey(const Key('occurred-at')),
      '2026-07-31 21:15',
    );
    await tester.enterText(find.byKey(const Key('milestone-title')), '第一次翻身');
    await tapSave(tester);
    await tester.pumpAndSettle();

    expect(
      repository.createInput?.occurredAt,
      DateTime(2026, 7, 31, 21, 15).toUtc(),
    );
  });

  testWidgets(
    'rejects an overflow calendar date and clears the error on edit',
    (tester) async {
      final repository = _EditorRepository();
      await pumpEditor(
        tester,
        type: RecordType.milestone,
        repository: repository,
      );
      await tester.enterText(find.byKey(const Key('milestone-title')), '第一次翻身');
      await tester.enterText(
        find.byKey(const Key('occurred-at')),
        '2026-02-30 09:00',
      );

      await tapSave(tester);
      await tester.pump();
      expect(find.text('请输入有效的发生时间。'), findsOneWidget);
      expect(repository.createInput, isNull);

      await tester.enterText(
        find.byKey(const Key('occurred-at')),
        '2026-02-28 09:00',
      );
      await tester.pump();
      expect(find.text('请输入有效的发生时间。'), findsNothing);
    },
  );

  testWidgets('editing completely prefills fields and existing attachments', (
    tester,
  ) async {
    final localOccurredAt = DateTime(2026, 7, 31, 21, 15);
    final existing = TimelineRecord(
      id: 'activity-1',
      type: RecordType.activity,
      occurredAt: localOccurredAt.toUtc(),
      note: '睡前奶',
      details: const RecordDetails.activity(
        activityType: ActivityType.feeding,
        amount: 120,
        durationMinutes: 15,
      ),
      attachments: [
        Attachment(
          id: 'photo-1',
          recordId: 'activity-1',
          mediaType: MediaType.image,
          filePath: '/media/photo.jpg',
          thumbnailPath: '/media/photo-thumb.jpg',
          createdAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    final repository = _EditorRepository(records: {'activity-1': existing});
    await pumpEditor(
      tester,
      type: RecordType.activity,
      recordId: 'activity-1',
      repository: repository,
    );

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('record-note')))
          .controller!
          .text,
      '睡前奶',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('occurred-at')))
          .controller!
          .text,
      '2026-07-31 21:15',
    );
    expect(
      tester
          .widget<DropdownButton<ActivityType>>(
            find.descendant(
              of: find.byKey(const Key('activity-type')),
              matching: find.byType(DropdownButton<ActivityType>),
            ),
          )
          .value,
      ActivityType.feeding,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('activity-amount')))
          .controller!
          .text,
      '120',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('activity-duration')))
          .controller!
          .text,
      '15',
    );
    expect(find.text('已有附件 1 个'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);

    await tapSave(tester);
    await tester.pumpAndSettle();
    expect(repository.updateInput?.attachments, const [
      NewAttachmentInput(
        id: 'photo-1',
        mediaType: MediaType.image,
        filePath: '/media/photo.jpg',
        thumbnailPath: '/media/photo-thumb.jpg',
      ),
    ]);
  });

  testWidgets('editing updates values without losing milestone metadata', (
    tester,
  ) async {
    final existing = TimelineRecord(
      id: 'milestone-1',
      type: RecordType.milestone,
      occurredAt: DateTime.utc(2026, 7, 31, 21, 15),
      details: const RecordDetails.milestone(
        title: '会翻身',
        presetKey: 'rolling-over',
      ),
      createdAt: now,
      updatedAt: now,
    );
    final repository = _EditorRepository(records: {'milestone-1': existing});
    await pumpEditor(
      tester,
      type: RecordType.milestone,
      recordId: 'milestone-1',
      repository: repository,
    );

    await tester.enterText(find.byKey(const Key('milestone-title')), '第一次独立翻身');
    await tapSave(tester);
    await tester.pumpAndSettle();

    expect(repository.createInput, isNull);
    expect(
      repository.updateInput?.details,
      const RecordDetails.milestone(
        title: '第一次独立翻身',
        presetKey: 'rolling-over',
      ),
    );
  });

  testWidgets('disables save while submission is in progress', (tester) async {
    final saveCompleter = Completer<TimelineRecord>();
    final repository = _EditorRepository(createFuture: saveCompleter.future);
    await pumpEditor(
      tester,
      type: RecordType.milestone,
      repository: repository,
    );
    await tester.enterText(find.byKey(const Key('milestone-title')), '第一次翻身');
    await tapSave(tester);
    await tester.pump();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    saveCompleter.complete(_savedRecord(RecordType.milestone));
    await tester.pump();
  });

  testWidgets('keeps save disabled while post-save work is in progress', (
    tester,
  ) async {
    final postSave = Completer<void>();
    final repository = _EditorRepository();
    await pumpEditor(
      tester,
      type: RecordType.milestone,
      repository: repository,
      onSaved: () => postSave.future,
    );
    await tester.enterText(find.byKey(const Key('milestone-title')), '第一次翻身');
    await tapSave(tester);
    await tester.pump();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    postSave.complete();
    await tester.pump();
  });

  testWidgets(
    'successful persistence stays terminal when post-save work fails',
    (tester) async {
      final repository = _EditorRepository();
      await pumpEditor(
        tester,
        type: RecordType.milestone,
        repository: repository,
        onSaved: () => Future<void>.error(StateError('refresh failed')),
      );
      await tester.enterText(find.byKey(const Key('milestone-title')), '第一次翻身');

      await tapSave(tester);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(repository.createCount, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.text('记录已保存，但页面刷新失败，请返回后查看。'), findsOneWidget);
      expect(find.text('保存失败，已有数据未受影响'), findsNothing);
    },
  );

  testWidgets('post-save failure offers recovery without persisting again', (
    tester,
  ) async {
    final repository = _EditorRepository();
    final router = GoRouter(
      initialLocation: '/editor',
      routes: [
        GoRoute(
          path: '/editor',
          builder: (context, state) => RecordEditorPage(
            type: RecordType.milestone,
            repository: repository,
            now: () => now,
            onSaved: () => Future<void>.error(StateError('refresh failed')),
          ),
        ),
        GoRoute(
          path: '/timeline',
          builder: (context, state) => const Scaffold(body: Text('已返回时间轴')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('milestone-title')), '第一次翻身');
    await tapSave(tester);
    await tester.pump();

    await tester.tap(find.text('返回时间轴'));
    await tester.pumpAndSettle();

    expect(find.text('已返回时间轴'), findsOneWidget);
    expect(repository.createCount, 1);
  });

  testWidgets('clears a validation message when the draft changes', (
    tester,
  ) async {
    final repository = _EditorRepository();
    await pumpEditor(
      tester,
      type: RecordType.milestone,
      repository: repository,
    );
    await tapSave(tester);
    await tester.pump();
    expect(find.text('请输入里程碑标题。'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('milestone-title')), '第一次翻身');
    await tester.pump();
    expect(find.text('请输入里程碑标题。'), findsNothing);
  });

  testWidgets(
    'retains form input and shows a failure message when saving fails',
    (tester) async {
      final repository = _EditorRepository(createError: StateError('offline'));
      await pumpEditor(
        tester,
        type: RecordType.milestone,
        repository: repository,
      );
      await tester.enterText(find.byKey(const Key('milestone-title')), '第一次翻身');
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.text('保存失败，已有数据未受影响'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('milestone-title')))
            .controller!
            .text,
        '第一次翻身',
      );
    },
  );

  test('persists a picked attachment through the media coordinator', () async {
    final repository = _EditorRepository();
    final controller = RecordEditorController(
      repository,
      type: RecordType.moment,
      now: () => now,
      mediaService: _EditorMediaService(),
    );
    controller.updateDraft(
      controller.draft.copyWith(
        note: '第一次微笑',
        attachments: const [
          RecordDraftAttachment.picked(
            sourcePath: '/tmp/new.jpg',
            mediaType: MediaType.image,
          ),
        ],
      ),
    );

    final saved = await controller.submit();

    expect(saved, isNotNull);
    expect(controller.validationError, isNull);
    expect(repository.createInput!.attachments, const [
      NewAttachmentInput(
        mediaType: MediaType.image,
        filePath: '/support/media/originals/photo.jpg',
        thumbnailPath: '/support/media/thumbnails/photo.jpg',
      ),
    ]);
  });

  test(
    'ignores a concurrent submit while persistence is in progress',
    () async {
      final saveCompleter = Completer<TimelineRecord>();
      final repository = _EditorRepository(createFuture: saveCompleter.future);
      final controller = RecordEditorController(
        repository,
        type: RecordType.milestone,
        now: () => now,
      );
      controller.updateDraft(
        controller.draft.copyWith(
          details: const RecordDetails.milestone(title: '第一次翻身'),
        ),
      );

      final first = controller.submit();
      final second = controller.submit();

      expect(repository.createCount, 1);
      saveCompleter.complete(_savedRecord(RecordType.milestone));
      await Future.wait([first, second]);
    },
  );

  test(
    'rejects an injected controller with incompatible parameters at runtime',
    () {
      final createController = RecordEditorController(
        _EditorRepository(),
        type: RecordType.moment,
        now: () => now,
      );
      final editController = RecordEditorController(
        _EditorRepository(),
        type: RecordType.milestone,
        recordId: 'record-1',
        now: () => now,
      );

      expect(
        () => RecordEditorPage(
          type: RecordType.growth,
          controller: createController,
        ),
        throwsArgumentError,
      );
      expect(
        () => RecordEditorPage(
          type: RecordType.milestone,
          recordId: 'record-2',
          controller: editController,
        ),
        throwsArgumentError,
      );
    },
  );
}

TimelineRecord _savedRecord(RecordType type) => TimelineRecord(
  id: 'saved',
  type: type,
  occurredAt: DateTime(2026, 8, 1, 9, 30),
  createdAt: DateTime(2026, 8, 1, 9, 30),
  updatedAt: DateTime(2026, 8, 1, 9, 30),
);

class _EditorRepository implements RecordRepository {
  _EditorRepository({
    Map<String, TimelineRecord>? records,
    this.createFuture,
    this.createError,
  }) : records = records ?? {};

  final Map<String, TimelineRecord> records;
  final Future<TimelineRecord>? createFuture;
  final Object? createError;
  NewRecordInput? createInput;
  NewRecordInput? updateInput;
  var createCount = 0;

  @override
  Future<TimelineRecord> create(NewRecordInput input) {
    createCount += 1;
    createInput = input;
    if (createError != null) return Future.error(createError!);
    return createFuture ?? Future.value(_savedRecord(input.type));
  }

  @override
  Future<List<Attachment>> delete(String id) => throw UnimplementedError();

  @override
  Future<TimelineRecord?> get(String id) async => records[id];

  @override
  Future<T> inTransaction<T>(Future<T> Function(RecordTransaction) work) =>
      work(this);

  @override
  Future<List<TimelineRecord>> list({Set<RecordType> types = const {}}) =>
      throw UnimplementedError();

  @override
  Future<TimelineRecord> update(String id, NewRecordInput input) async {
    updateInput = input;
    return _savedRecord(input.type);
  }
}

class _EditorMediaService implements MediaService {
  @override
  Future<StagedMedia> stage(PickedMedia input) async => StagedMedia(
    stagingPath: '/support/staging/photo.jpg',
    finalPath: '/support/media/originals/photo.jpg',
    mediaType: input.mediaType,
    thumbnailStagingPath: '/support/staging/photo-thumb.jpg',
    thumbnailFinalPath: '/support/media/thumbnails/photo.jpg',
  );

  @override
  Future<CommittedMedia> commit(StagedMedia staged) async => CommittedMedia(
    filePath: staged.finalPath,
    thumbnailPath: staged.thumbnailFinalPath,
  );

  @override
  Future<void> remove(Iterable<String> paths) async {}

  @override
  Future<void> removeOrphans(Set<String> referencedPaths) async {}

  @override
  Future<void> rollback(StagedMedia staged) async {}
}
