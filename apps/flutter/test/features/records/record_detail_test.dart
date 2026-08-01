import 'dart:async';

import 'package:baby_growth_timeline/data/repositories/record_repository.dart';
import 'package:baby_growth_timeline/domain/models/attachment.dart';
import 'package:baby_growth_timeline/domain/models/record_draft.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';
import 'package:baby_growth_timeline/features/records/presentation/record_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TimelineRecord record({
    required String id,
    required RecordType type,
    required RecordDetails? details,
    List<Attachment> attachments = const [],
  }) => TimelineRecord(
    id: id,
    type: type,
    occurredAt: DateTime.utc(2026, 8, 1, 9),
    details: details,
    attachments: attachments,
    createdAt: DateTime.utc(2026, 8, 1, 9),
    updatedAt: DateTime.utc(2026, 8, 1, 9),
  );

  Future<void> pumpDetail(
    WidgetTester tester, {
    required _DetailRepository repository,
    String id = 'growth',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecordDetailPage(recordId: id, repository: repository),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows growth values with centimetre and kilogram units', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      repository: _DetailRepository({
        'growth': record(
          id: 'growth',
          type: RecordType.growth,
          details: const RecordDetails.growth(
            heightCm: 68.5,
            weightKg: 7.4,
            headCm: 42.1,
          ),
        ),
      }),
    );

    expect(find.text('68.5 cm'), findsOneWidget);
    expect(find.text('7.4 kg'), findsOneWidget);
    expect(find.text('42.1 cm'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('shows a placeholder when an attachment file is unavailable', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      repository: _DetailRepository({
        'moment': record(
          id: 'moment',
          type: RecordType.moment,
          details: null,
          attachments: [
            Attachment(
              id: 'gone',
              recordId: 'moment',
              mediaType: MediaType.image,
              filePath: '/definitely/missing/photo.jpg',
              createdAt: DateTime.utc(2026, 8, 1, 9),
            ),
          ],
        ),
      }),
      id: 'moment',
    );

    expect(find.text('媒体文件不可用'), findsOneWidget);
  });

  testWidgets('shows missing record and retries a read error', (tester) async {
    final repository = _DetailRepository({});
    await pumpDetail(tester, repository: repository);
    expect(find.text('记录不存在'), findsOneWidget);

    repository.error = StateError('offline');
    await tester.pumpWidget(
      MaterialApp(
        home: RecordDetailPage(recordId: 'retry', repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法读取记录，请重试'), findsOneWidget);

    repository.error = null;
    repository.records['retry'] = record(
      id: 'retry',
      type: RecordType.milestone,
      details: const RecordDetails.milestone(title: '第一次独站'),
    );
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('第一次独站'), findsOneWidget);
  });

  testWidgets('ignores a stale record read after recordId changes', (
    tester,
  ) async {
    final first = Completer<TimelineRecord?>();
    final second = Completer<TimelineRecord?>();
    final repository = _ControlledDetailRepository([first, second]);
    final latest = record(
      id: 'second',
      type: RecordType.milestone,
      details: const RecordDetails.milestone(title: '最新记录'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RecordDetailPage(recordId: 'first', repository: repository),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: RecordDetailPage(recordId: 'second', repository: repository),
      ),
    );
    await tester.pump();

    second.complete(latest);
    await tester.pumpAndSettle();
    first.completeError(StateError('stale request failed'));
    await tester.pumpAndSettle();

    expect(find.text('最新记录'), findsOneWidget);
    expect(find.text('无法读取记录，请重试'), findsNothing);
  });

  testWidgets('ignores stale record data after recordId changes', (
    tester,
  ) async {
    final first = Completer<TimelineRecord?>();
    final second = Completer<TimelineRecord?>();
    final repository = _ControlledDetailRepository([first, second]);
    final latest = record(
      id: 'second',
      type: RecordType.milestone,
      details: const RecordDetails.milestone(title: '最新记录'),
    );
    final stale = record(
      id: 'first',
      type: RecordType.milestone,
      details: const RecordDetails.milestone(title: '旧记录'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RecordDetailPage(recordId: 'first', repository: repository),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: RecordDetailPage(recordId: 'second', repository: repository),
      ),
    );
    await tester.pump();

    second.complete(latest);
    await tester.pumpAndSettle();
    first.complete(stale);
    await tester.pumpAndSettle();

    expect(find.text('最新记录'), findsOneWidget);
    expect(find.text('旧记录'), findsNothing);
  });
}

class _DetailRepository implements RecordRepository {
  _DetailRepository(this.records);

  final Map<String, TimelineRecord> records;
  Object? error;

  @override
  Future<TimelineRecord> create(NewRecordInput input) =>
      throw UnimplementedError();

  @override
  Future<List<Attachment>> delete(String id) => throw UnimplementedError();

  @override
  Future<TimelineRecord?> get(String id) async {
    if (error != null) throw error!;
    return records[id];
  }

  @override
  Future<T> inTransaction<T>(Future<T> Function(RecordTransaction) work) =>
      throw UnimplementedError();

  @override
  Future<List<TimelineRecord>> list({Set<RecordType> types = const {}}) =>
      throw UnimplementedError();

  @override
  Future<TimelineRecord> update(String id, NewRecordInput input) =>
      throw UnimplementedError();
}

class _ControlledDetailRepository extends _DetailRepository {
  _ControlledDetailRepository(this._completers) : super({});

  final List<Completer<TimelineRecord?>> _completers;
  var _next = 0;

  @override
  Future<TimelineRecord?> get(String id) => _completers[_next++].future;
}
