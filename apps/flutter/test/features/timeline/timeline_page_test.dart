import 'dart:async';
import 'dart:io';

import 'package:baby_growth_timeline/data/repositories/record_repository.dart';
import 'package:baby_growth_timeline/domain/models/attachment.dart';
import 'package:baby_growth_timeline/domain/models/record_draft.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';
import 'package:baby_growth_timeline/features/timeline/application/timeline_controller.dart';
import 'package:baby_growth_timeline/features/timeline/presentation/timeline_card.dart';
import 'package:baby_growth_timeline/features/timeline/presentation/timeline_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/media_fixture.dart';

void main() {
  final now = DateTime(2026, 8, 1, 12);
  late Directory mediaDirectory;

  setUp(() {
    mediaDirectory = Directory.systemTemp.createTempSync(
      'timeline-card-media-',
    );
  });

  tearDown(() {
    if (mediaDirectory.existsSync()) {
      mediaDirectory.deleteSync(recursive: true);
    }
  });

  TimelineRecord record({
    required String id,
    required RecordType type,
    required DateTime occurredAt,
    String? note,
    RecordDetails? details,
    List<Attachment> attachments = const [],
  }) => TimelineRecord(
    id: id,
    type: type,
    occurredAt: occurredAt.toUtc(),
    note: note,
    details: details,
    attachments: attachments,
    createdAt: occurredAt.toUtc(),
    updatedAt: occurredAt.toUtc(),
  );

  Future<void> pumpTimeline(
    WidgetTester tester,
    TimelineController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePage(
            hasBaby: true,
            controller: controller,
            now: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('groups records into today yesterday and a calendar date', (
    tester,
  ) async {
    final controller = TimelineController(
      _FakeRecordRepository([
        record(
          id: 'morning',
          type: RecordType.moment,
          occurredAt: DateTime(2026, 8, 1, 8),
          note: '早安微笑',
        ),
        record(
          id: 'evening',
          type: RecordType.growth,
          occurredAt: DateTime(2026, 8, 1, 21, 30),
          details: const RecordDetails.growth(heightCm: 68.5, weightKg: 7.4),
        ),
        record(
          id: 'yesterday',
          type: RecordType.activity,
          occurredAt: DateTime(2026, 7, 31, 14),
          note: '午觉',
          details: const RecordDetails.activity(
            activityType: ActivityType.sleep,
            durationMinutes: 95,
          ),
        ),
        record(
          id: 'older',
          type: RecordType.milestone,
          occurredAt: DateTime(2026, 7, 29, 10),
          details: const RecordDetails.milestone(title: '第一次独站'),
        ),
      ]),
    );

    await pumpTimeline(tester, controller);

    expect(find.text('今天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.text('2026年7月29日'), findsOneWidget);
    expect(find.text('21:30'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('21:30')).dy,
      lessThan(tester.getTopLeft(find.text('08:00')).dy),
    );
  });

  testWidgets('filters by type and clears back to all record types', (
    tester,
  ) async {
    final controller = TimelineController(
      _FakeRecordRepository([
        record(
          id: 'moment',
          type: RecordType.moment,
          occurredAt: DateTime(2026, 8, 1, 8),
          note: '第一次微笑',
        ),
        record(
          id: 'growth',
          type: RecordType.growth,
          occurredAt: DateTime(2026, 8, 1, 9),
          details: const RecordDetails.growth(heightCm: 68.5),
        ),
      ]),
    );

    await pumpTimeline(tester, controller);
    await tester.tap(find.text('成长'));
    await tester.pumpAndSettle();

    expect(find.text('68.5 cm'), findsOneWidget);
    expect(find.text('第一次微笑'), findsNothing);
    expect(find.text('清除筛选'), findsOneWidget);

    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();

    expect(find.text('68.5 cm'), findsOneWidget);
    expect(find.text('第一次微笑'), findsOneWidget);
  });

  testWidgets(
    'shows a summary for each compact record type and an empty state',
    (tester) async {
      final controller = TimelineController(
        _FakeRecordRepository([
          record(
            id: 'growth',
            type: RecordType.growth,
            occurredAt: DateTime(2026, 8, 1, 9),
            details: const RecordDetails.growth(heightCm: 68.5, weightKg: 7.4),
          ),
          record(
            id: 'sleep',
            type: RecordType.activity,
            occurredAt: DateTime(2026, 8, 1, 8),
            details: const RecordDetails.activity(
              activityType: ActivityType.sleep,
              durationMinutes: 95,
            ),
          ),
          record(
            id: 'milestone',
            type: RecordType.milestone,
            occurredAt: DateTime(2026, 8, 1, 7),
            details: const RecordDetails.milestone(title: '第一次独站'),
          ),
        ]),
      );
      await pumpTimeline(tester, controller);

      expect(find.text('68.5 cm · 7.4 kg'), findsOneWidget);
      expect(find.text('睡眠 · 95 分钟'), findsOneWidget);
      expect(find.text('第一次独站'), findsOneWidget);

      await pumpTimeline(tester, TimelineController(_FakeRecordRepository([])));
      expect(find.text('还没有成长记录'), findsOneWidget);
    },
  );

  test('retains loaded records and allows retry when reload fails', () async {
    final repository = _FakeRecordRepository([
      record(
        id: 'moment',
        type: RecordType.moment,
        occurredAt: DateTime(2026, 8, 1, 8),
        note: '第一次微笑',
      ),
    ]);
    final controller = TimelineController(repository);

    await controller.load();
    repository.listError = StateError('offline');
    await controller.reload();

    expect(controller.state.records.single.note, '第一次微笑');
    expect(controller.state.errorMessage, '无法读取记录，请重试');

    repository.listError = null;
    await controller.reload();
    expect(controller.state.errorMessage, isNull);
  });

  test('ignores an older reload completion after the filter changes', () async {
    final first = Completer<List<TimelineRecord>>();
    final second = Completer<List<TimelineRecord>>();
    final growth = record(
      id: 'growth',
      type: RecordType.growth,
      occurredAt: DateTime(2026, 8, 1, 9),
      details: const RecordDetails.growth(heightCm: 68.5),
    );
    final controller = TimelineController(
      _ControlledListRepository([first, second]),
    );

    controller.load();
    final applyGrowthFilter = controller.toggleType(RecordType.growth);
    second.complete([growth]);
    await applyGrowthFilter;
    first.completeError(StateError('stale request failed'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.selectedTypes, {RecordType.growth});
    expect(controller.state.records, [growth]);
    expect(controller.state.errorMessage, isNull);
  });

  test('ignores stale records returned by an older reload', () async {
    final first = Completer<List<TimelineRecord>>();
    final second = Completer<List<TimelineRecord>>();
    final oldMoment = record(
      id: 'old-moment',
      type: RecordType.moment,
      occurredAt: DateTime(2026, 8, 1, 8),
      note: '旧记录',
    );
    final growth = record(
      id: 'growth',
      type: RecordType.growth,
      occurredAt: DateTime(2026, 8, 1, 9),
      details: const RecordDetails.growth(heightCm: 68.5),
    );
    final controller = TimelineController(
      _ControlledListRepository([first, second]),
    );

    controller.load();
    final applyGrowthFilter = controller.toggleType(RecordType.growth);
    second.complete([growth]);
    await applyGrowthFilter;
    first.complete([oldMoment]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.selectedTypes, {RecordType.growth});
    expect(controller.state.records, [growth]);
  });

  test('uses a neutral amount label when an activity has no duration', () {
    final feeding = record(
      id: 'feeding',
      type: RecordType.activity,
      occurredAt: DateTime(2026, 8, 1, 9),
      details: const RecordDetails.activity(
        activityType: ActivityType.feeding,
        amount: 120,
      ),
    );

    expect(recordSummary(feeding), '喂养 · 数量 120');
  });

  test('uses the preceding local calendar date for yesterday', () {
    expect(timelineDayLabel('2024-03-10', DateTime(2024, 3, 11, 12)), '昨天');
  });

  testWidgets('moment card renders its first existing image file', (
    tester,
  ) async {
    final image = writeValidPng(mediaDirectory, 'moment.png');
    final moment = record(
      id: 'image-moment',
      type: RecordType.moment,
      occurredAt: now,
      attachments: [
        Attachment(
          id: 'image',
          recordId: 'image-moment',
          mediaType: MediaType.image,
          filePath: image.path,
          createdAt: now.toUtc(),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TimelineCard(record: moment, onTap: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moment card renders a video thumbnail with play affordance', (
    tester,
  ) async {
    final video = File('${mediaDirectory.path}/moment.mp4');
    video.writeAsBytesSync(const [0]);
    final thumbnail = writeValidPng(mediaDirectory, 'video-thumb.png');
    final moment = record(
      id: 'video-moment',
      type: RecordType.moment,
      occurredAt: now,
      attachments: [
        Attachment(
          id: 'video',
          recordId: 'video-moment',
          mediaType: MediaType.video,
          filePath: video.path,
          thumbnailPath: thumbnail.path,
          createdAt: now.toUtc(),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TimelineCard(record: moment, onTap: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moment card reports a missing media file', (tester) async {
    TimelineRecord momentWithPath(String path) => record(
      id: 'unavailable-moment',
      type: RecordType.moment,
      occurredAt: now,
      attachments: [
        Attachment(
          id: 'image',
          recordId: 'unavailable-moment',
          mediaType: MediaType.image,
          filePath: path,
          createdAt: now.toUtc(),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TimelineCard(
          record: momentWithPath('${mediaDirectory.path}/missing.png'),
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('媒体文件不可用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moment card reports an image decode failure', (tester) async {
    final corrupt = File('${mediaDirectory.path}/corrupt.png');
    corrupt.writeAsStringSync('not an image');
    final moment = record(
      id: 'corrupt-moment',
      type: RecordType.moment,
      occurredAt: now,
      attachments: [
        Attachment(
          id: 'image',
          recordId: 'corrupt-moment',
          mediaType: MediaType.image,
          filePath: corrupt.path,
          createdAt: now.toUtc(),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TimelineCard(record: moment, onTap: () {}),
      ),
    );
    await pumpUntilVisible(tester, find.text('媒体文件不可用'));

    expect(find.text('媒体文件不可用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moment card keeps its placeholder when there is no attachment', (
    tester,
  ) async {
    final moment = record(
      id: 'empty-moment',
      type: RecordType.moment,
      occurredAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TimelineCard(record: moment, onTap: () {}),
      ),
    );

    expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
    expect(find.text('媒体文件不可用'), findsNothing);
  });

  testWidgets('matches the stable mixed timeline layout', (tester) async {
    final controller = TimelineController(
      _FakeRecordRepository([
        record(
          id: 'moment',
          type: RecordType.moment,
          occurredAt: DateTime(2026, 8, 1, 9),
          note: '第一次微笑',
        ),
        record(
          id: 'growth',
          type: RecordType.growth,
          occurredAt: DateTime(2026, 8, 1, 8),
          details: const RecordDetails.growth(heightCm: 68.5, weightKg: 7.4),
        ),
        record(
          id: 'sleep',
          type: RecordType.activity,
          occurredAt: DateTime(2026, 7, 31, 14),
          details: const RecordDetails.activity(
            activityType: ActivityType.sleep,
            durationMinutes: 95,
          ),
        ),
      ]),
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1)),
          child: Scaffold(
            body: TimelinePage(
              hasBaby: true,
              controller: controller,
              now: () => now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('../../goldens/timeline_mixed.png'),
    );
  });
}

class _FakeRecordRepository implements RecordRepository {
  _FakeRecordRepository(this.records);

  final List<TimelineRecord> records;
  Object? listError;

  @override
  Future<TimelineRecord> create(NewRecordInput input) =>
      throw UnimplementedError();

  @override
  Future<List<Attachment>> delete(String id) => throw UnimplementedError();

  @override
  Future<TimelineRecord?> get(String id) async => records
      .cast<TimelineRecord?>()
      .firstWhere((record) => record?.id == id, orElse: () => null);

  @override
  Future<T> inTransaction<T>(Future<T> Function(RecordTransaction) work) =>
      throw UnimplementedError();

  @override
  Future<List<TimelineRecord>> list({Set<RecordType> types = const {}}) async {
    if (listError != null) throw listError!;
    final selected = types.isEmpty
        ? records
        : records.where((record) => types.contains(record.type)).toList();
    return selected;
  }

  @override
  Future<TimelineRecord> update(String id, NewRecordInput input) =>
      throw UnimplementedError();
}

class _ControlledListRepository extends _FakeRecordRepository {
  _ControlledListRepository(this._completers) : super([]);

  final List<Completer<List<TimelineRecord>>> _completers;
  var _next = 0;

  @override
  Future<List<TimelineRecord>> list({Set<RecordType> types = const {}}) =>
      _completers[_next++].future;
}
