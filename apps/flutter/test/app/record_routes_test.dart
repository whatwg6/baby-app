import 'dart:async';

import 'package:baby_growth_timeline/app/app.dart';
import 'package:baby_growth_timeline/app/router.dart';
import 'package:baby_growth_timeline/data/repositories/record_repository.dart';
import 'package:baby_growth_timeline/domain/models/attachment.dart';
import 'package:baby_growth_timeline/domain/models/record_draft.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';
import 'package:baby_growth_timeline/features/timeline/application/timeline_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Future<GoRouter> pumpApp(
    WidgetTester tester,
    _RouteRepository repository, {
    TimelineController? timelineController,
  }) async {
    final router = createRouter(
      hasBaby: true,
      recordRepository: repository,
      timelineController: timelineController,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(BabyTimelineApp(router: router));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('unfinished Add draft survives switching tabs', (tester) async {
    final repository = _RouteRepository();
    final router = await pumpApp(tester, repository);

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('里程碑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('milestone-title')), '待保存草稿');

    await tester.tap(find.text('时间轴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/add/milestone');
    expect(find.byKey(const Key('milestone-title')), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('milestone-title')))
          .controller!
          .text,
      '待保存草稿',
    );
    expect(repository.createCount, 0);
  });

  testWidgets('create resets Add once and then preserves the next draft', (
    tester,
  ) async {
    final repository = _RouteRepository();
    final router = await pumpApp(tester, repository);

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('里程碑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('milestone-title')), '第一次翻身');
    final transitions = <String>[];
    void recordTransition() =>
        transitions.add(router.routeInformationProvider.value.uri.path);
    router.routeInformationProvider.addListener(recordTransition);
    addTearDown(
      () => router.routeInformationProvider.removeListener(recordTransition),
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/timeline');
    expect(transitions, isNot(contains('/add')));
    expect(find.text('第一次翻身'), findsOneWidget);
    expect(repository.createCount, 1);

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(find.text('添加成长记录'), findsOneWidget);
    expect(find.byKey(const Key('milestone-title')), findsNothing);
    expect(repository.createCount, 1);

    await tester.tap(find.text('里程碑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('milestone-title')), '第二条草稿');
    await tester.tap(find.text('时间轴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/add/milestone');
    expect(find.byKey(const Key('milestone-title')), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('milestone-title')))
          .controller!
          .text,
      '第二条草稿',
    );
    expect(repository.createCount, 1);
  });

  testWidgets('reload completion does not override a later tab choice', (
    tester,
  ) async {
    final repository = _RouteRepository();
    final router = await pumpApp(tester, repository);
    final reloadBarrier = Completer<void>();
    repository.nextListBarrier = reloadBarrier;

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('里程碑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('milestone-title')), '第一次翻身');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(repository.listCount, 2);

    await tester.tap(find.text('宝宝'));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/baby');

    reloadBarrier.complete();
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/baby');
  });

  testWidgets('reload failure still leaves the next Add tab at its picker', (
    tester,
  ) async {
    final repository = _RouteRepository();
    final router = await pumpApp(
      tester,
      repository,
      timelineController: _ThrowingReloadTimelineController(repository),
    );

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('里程碑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('milestone-title')), '第一次翻身');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/timeline');

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(find.text('添加成长记录'), findsOneWidget);
    expect(find.byKey(const Key('milestone-title')), findsNothing);
    expect(repository.createCount, 1);
  });

  testWidgets('add route parameter changes rebuild the typed editor', (
    tester,
  ) async {
    final repository = _RouteRepository();
    final router = await pumpApp(tester, repository);

    router.go('/add/growth');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('growth-height')), findsOneWidget);

    router.go('/add/milestone');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('milestone-title')), findsOneWidget);
    expect(find.byKey(const Key('growth-height')), findsNothing);

    router.go('/add/not-a-record-type');
    await tester.pumpAndSettle();
    expect(find.text('宝宝资料暂不可用'), findsOneWidget);
  });

  testWidgets('edit route record ID changes reload the matching record', (
    tester,
  ) async {
    final repository = _RouteRepository(
      records: {
        'first': _milestone('first', '第一条'),
        'second': _activity('second', ActivityType.sleep, 30),
      },
    );
    final router = await pumpApp(tester, repository);

    router.go('/records/first/edit?type=milestone');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('milestone-title')))
          .controller!
          .text,
      '第一条',
    );

    router.go('/records/second/edit?type=activity');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-type')), findsOneWidget);
    expect(find.byKey(const Key('milestone-title')), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('activity-duration')))
          .controller!
          .text,
      '30',
    );
  });

  testWidgets('edit pop result refreshes both detail and timeline', (
    tester,
  ) async {
    final repository = _RouteRepository(
      records: {'milestone-1': _milestone('milestone-1', '旧标题')},
    );
    final router = await pumpApp(tester, repository);
    router.go('/records/milestone-1');
    await tester.pumpAndSettle();
    expect(find.text('旧标题'), findsOneWidget);
    final listCountBeforeEdit = repository.listCount;

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('milestone-title')), '更新后的标题');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      '/records/milestone-1',
    );
    expect(find.text('更新后的标题'), findsOneWidget);
    expect(repository.updateCount, 1);
    expect(repository.getCount, greaterThanOrEqualTo(3));
    expect(repository.listCount, greaterThan(listCountBeforeEdit));
  });
}

TimelineRecord _milestone(String id, String title) => TimelineRecord(
  id: id,
  type: RecordType.milestone,
  occurredAt: DateTime.utc(2026, 8, 1, 9),
  details: RecordDetails.milestone(title: title),
  createdAt: DateTime.utc(2026, 8, 1, 9),
  updatedAt: DateTime.utc(2026, 8, 1, 9),
);

TimelineRecord _activity(
  String id,
  ActivityType activityType,
  int durationMinutes,
) => TimelineRecord(
  id: id,
  type: RecordType.activity,
  occurredAt: DateTime.utc(2026, 8, 1, 8),
  details: RecordDetails.activity(
    activityType: activityType,
    durationMinutes: durationMinutes,
  ),
  createdAt: DateTime.utc(2026, 8, 1, 8),
  updatedAt: DateTime.utc(2026, 8, 1, 8),
);

class _RouteRepository implements RecordRepository {
  _RouteRepository({Map<String, TimelineRecord>? records})
    : records = records ?? {};

  final Map<String, TimelineRecord> records;
  var createCount = 0;
  var updateCount = 0;
  var getCount = 0;
  var listCount = 0;
  Completer<void>? nextListBarrier;

  @override
  Future<TimelineRecord> create(NewRecordInput input) async {
    createCount += 1;
    final id = 'created-$createCount';
    final record = _fromInput(id, input);
    records[id] = record;
    return record;
  }

  @override
  Future<TimelineRecord> update(String id, NewRecordInput input) async {
    updateCount += 1;
    final record = _fromInput(id, input, previous: records[id]);
    records[id] = record;
    return record;
  }

  @override
  Future<TimelineRecord?> get(String id) async {
    getCount += 1;
    return records[id];
  }

  @override
  Future<List<TimelineRecord>> list({Set<RecordType> types = const {}}) async {
    listCount += 1;
    final barrier = nextListBarrier;
    nextListBarrier = null;
    await barrier?.future;
    final result =
        records.values
            .where((record) => types.isEmpty || types.contains(record.type))
            .toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return result;
  }

  @override
  Future<List<Attachment>> delete(String id) async =>
      records.remove(id)?.attachments ?? const [];

  @override
  Future<T> inTransaction<T>(
    Future<T> Function(RecordTransaction transaction) work,
  ) => work(this);
}

class _ThrowingReloadTimelineController extends TimelineController {
  _ThrowingReloadTimelineController(super.repository);

  @override
  Future<void> reload() => Future<void>.error(StateError('reload failed'));
}

TimelineRecord _fromInput(
  String id,
  NewRecordInput input, {
  TimelineRecord? previous,
}) {
  final now = DateTime.utc(2026, 8, 1, 10);
  return TimelineRecord(
    id: id,
    type: input.type,
    occurredAt: input.occurredAt,
    note: input.note,
    details: input.details,
    attachments: [
      for (final attachment in input.attachments)
        Attachment(
          id: attachment.id ?? 'attachment-$id',
          recordId: id,
          mediaType: attachment.mediaType,
          filePath: attachment.filePath,
          thumbnailPath: attachment.thumbnailPath,
          createdAt: now,
        ),
    ],
    createdAt: previous?.createdAt ?? now,
    updatedAt: now,
  );
}
