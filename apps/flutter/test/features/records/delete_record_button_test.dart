import 'package:baby_growth_timeline/data/repositories/baby_repository.dart';
import 'package:baby_growth_timeline/data/repositories/record_repository.dart';
import 'package:baby_growth_timeline/domain/models/attachment.dart';
import 'package:baby_growth_timeline/domain/models/baby.dart';
import 'package:baby_growth_timeline/domain/models/record_draft.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';
import 'package:baby_growth_timeline/features/baby/application/baby_controller.dart';
import 'package:baby_growth_timeline/features/baby/presentation/baby_page.dart';
import 'package:baby_growth_timeline/features/backup/presentation/backup_actions.dart';
import 'package:baby_growth_timeline/features/media/domain/media_service.dart';
import 'package:baby_growth_timeline/features/records/presentation/delete_record_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final attachment = Attachment(
    id: 'attachment-1',
    recordId: 'record-1',
    mediaType: MediaType.image,
    filePath: '/private/media/original.jpg',
    thumbnailPath: '/private/media/thumbnail.jpg',
    createdAt: DateTime.utc(2026, 8, 1),
  );

  Future<void> pumpDelete(
    WidgetTester tester, {
    required _DeleteRepository repository,
    required _RecordingMediaService mediaService,
    Future<void> Function(Set<String>)? queueOrphanCleanup,
    Future<void> Function()? onDeleted,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DeleteRecordButton(
          recordId: 'record-1',
          repository: repository,
          mediaService: mediaService,
          queueOrphanCleanup: queueOrphanCleanup ?? (_) async {},
          onDeleted: onDeleted,
        ),
      ),
    ),
  );

  testWidgets('cancel leaves the repository and media untouched', (
    tester,
  ) async {
    final events = <String>[];
    await pumpDelete(
      tester,
      repository: _DeleteRepository(attachment, events),
      mediaService: _RecordingMediaService(events),
    );

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除这条记录？此操作无法撤销。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(events, isEmpty);
  });

  testWidgets('confirmation commits database deletion before media cleanup', (
    tester,
  ) async {
    final events = <String>[];
    await pumpDelete(
      tester,
      repository: _DeleteRepository(attachment, events),
      mediaService: _RecordingMediaService(events),
      onDeleted: () async => events.add('notified'),
    );

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(events, [
      'database committed',
      'remove:/private/media/original.jpg,/private/media/thumbnail.jpg',
      'notified',
    ]);
  });

  testWidgets('media failure queues paths after the database commit', (
    tester,
  ) async {
    final events = <String>[];
    final queued = <String>{};
    await pumpDelete(
      tester,
      repository: _DeleteRepository(attachment, events),
      mediaService: _RecordingMediaService(events, failRemove: true),
      queueOrphanCleanup: (paths) async {
        events.add('queued');
        queued.addAll(paths);
      },
      onDeleted: () async => events.add('notified'),
    );

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(events, [
      'database committed',
      'remove:/private/media/original.jpg,/private/media/thumbnail.jpg',
      'queued',
      'notified',
    ]);
    expect(queued, {
      '/private/media/original.jpg',
      '/private/media/thumbnail.jpg',
    });
  });

  testWidgets('clear confirmation requires the exact current baby name', (
    tester,
  ) async {
    var clears = 0;
    final controller = BabyController(_BabyRepository());
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BabyPage(
            controller: controller,
            onClearAllData: () async => clears += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.text('清空所有数据'));
    await tester.pumpAndSettle();
    expect(find.text('将删除宝宝资料、全部记录和媒体，此操作无法撤销'), findsOneWidget);
    FilledButton confirm() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认清空'));
    expect(confirm().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('clear-baby-name')), ' 安安');
    await tester.pump();
    expect(confirm().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('clear-baby-name')), '安安');
    await tester.pump();
    expect(confirm().onPressed, isNotNull);
    await tester.tap(find.widgetWithText(FilledButton, '确认清空'));
    await tester.pumpAndSettle();

    expect(clears, 1);
  });

  testWidgets('clear reports post-commit cleanup failure distinctly', (
    tester,
  ) async {
    final controller = BabyController(_BabyRepository());
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BabyPage(
            controller: controller,
            onClearAllData: () async {
              throw ClearAllDataCleanupException(
                paths: {'/private/media/original.jpg'},
                mediaRemovalError: StateError('remove failed'),
                queueError: StateError('queue failed'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('清空所有数据'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('clear-baby-name')), '安安');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '确认清空'));
    await tester.pumpAndSettle();

    expect(find.text('数据已清空，但媒体清理排队失败'), findsOneWidget);
    expect(find.text('清空失败，请稍后重试'), findsNothing);
  });
}

class _DeleteRepository implements RecordRepository {
  _DeleteRepository(this.attachment, this.events);

  final Attachment attachment;
  final List<String> events;

  @override
  Future<List<Attachment>> delete(String id) async {
    events.add('database committed');
    return [attachment];
  }

  @override
  Future<TimelineRecord> create(NewRecordInput input) =>
      throw UnimplementedError();

  @override
  Future<TimelineRecord?> get(String id) => throw UnimplementedError();

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

class _RecordingMediaService implements MediaService {
  _RecordingMediaService(this.events, {this.failRemove = false});

  final List<String> events;
  final bool failRemove;

  @override
  Future<void> remove(Iterable<String> paths) async {
    events.add('remove:${paths.join(',')}');
    if (failRemove) throw StateError('disk unavailable');
  }

  @override
  Future<CommittedMedia> commit(StagedMedia staged) =>
      throw UnimplementedError();

  @override
  Future<void> removeOrphans(Set<String> referencedPaths) =>
      throw UnimplementedError();

  @override
  Future<void> rollback(StagedMedia staged) => throw UnimplementedError();

  @override
  Future<StagedMedia> stage(PickedMedia input) => throw UnimplementedError();
}

class _BabyRepository implements BabyRepository {
  final baby = Baby(
    id: 'baby-1',
    name: '安安',
    birthDate: '2025-06-15',
    createdAt: DateTime.utc(2025, 6, 15),
    updatedAt: DateTime.utc(2025, 6, 15),
  );

  @override
  Future<Baby?> getCurrent() async => baby;

  @override
  Future<Baby> create(BabyDraft draft) => throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();

  @override
  Future<Baby?> get(String id) => throw UnimplementedError();

  @override
  Future<Baby> update(String id, BabyDraft draft) => throw UnimplementedError();
}
