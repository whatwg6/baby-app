import 'package:baby_growth_timeline/data/repositories/record_repository.dart';
import 'package:baby_growth_timeline/domain/models/attachment.dart';
import 'package:baby_growth_timeline/domain/models/record_draft.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';
import 'package:baby_growth_timeline/features/media/application/save_record_with_media.dart';
import 'package:baby_growth_timeline/features/media/domain/media_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final occurredAt = DateTime.utc(2026, 8, 1, 8);

  RecordDraft draftWith(List<RecordDraftAttachment> attachments) => RecordDraft(
    type: RecordType.moment,
    occurredAt: occurredAt,
    note: '第一次微笑',
    attachments: attachments,
  );

  test(
    'orders stage, transactional final-path write, file commit, and DB commit',
    () async {
      final events = <String>[];
      final repository = _TransactionalRepository(events);
      final media = _TrackingMediaService(events);

      final saved = await saveRecordWithMedia(
        repository: repository,
        mediaService: media,
        draft: draftWith(const [
          RecordDraftAttachment.picked(
            sourcePath: '/picker/photo.JPG',
            mediaType: MediaType.image,
          ),
        ]),
      );

      expect(saved.id, 'record-1');
      expect(events, <String>[
        'files:stage:/picker/photo.JPG',
        'db:transaction:start',
        'db:create:/support/media/originals/0.jpg',
        'files:commit:/support/media/originals/0.jpg',
        'db:callback:return',
        'db:commit',
      ]);
      expect(
        repository.committedInput!.attachments.single.thumbnailPath,
        '/support/media/thumbnails/0.jpg',
      );
      expect(media.finalPaths, <String>{
        '/support/media/originals/0.jpg',
        '/support/media/thumbnails/0.jpg',
      });
    },
  );

  test('a later stage failure rolls back every earlier staged file', () async {
    final events = <String>[];
    final repository = _TransactionalRepository(events);
    final media = _TrackingMediaService(events, failStageAt: 1);

    await expectLater(
      saveRecordWithMedia(
        repository: repository,
        mediaService: media,
        draft: draftWith(const [
          RecordDraftAttachment.picked(
            sourcePath: '/picker/first.jpg',
            mediaType: MediaType.image,
          ),
          RecordDraftAttachment.picked(
            sourcePath: '/picker/second.jpg',
            mediaType: MediaType.image,
          ),
        ]),
      ),
      throwsStateError,
    );

    expect(repository.transactionCount, 0);
    expect(media.stagingPaths, isEmpty);
    expect(media.finalPaths, isEmpty);
    expect(events, contains('files:rollback:/support/media/originals/0.jpg'));
  });

  test(
    'a media commit failure rolls back SQLite and all staged/final files',
    () async {
      final events = <String>[];
      final repository = _TransactionalRepository(events);
      final media = _TrackingMediaService(events, failCommitAt: 1);

      await expectLater(
        saveRecordWithMedia(
          repository: repository,
          mediaService: media,
          draft: draftWith(const [
            RecordDraftAttachment.picked(
              sourcePath: '/picker/first.jpg',
              mediaType: MediaType.image,
            ),
            RecordDraftAttachment.picked(
              sourcePath: '/picker/second.jpg',
              mediaType: MediaType.image,
            ),
          ]),
        ),
        throwsStateError,
      );

      expect(repository.committedInput, isNull);
      expect(events, contains('db:rollback'));
      expect(media.stagingPaths, isEmpty);
      expect(media.finalPaths, isEmpty);
    },
  );

  test(
    'a DB callback failure removes staging without committing media',
    () async {
      final events = <String>[];
      final repository = _TransactionalRepository(
        events,
        writeError: StateError('insert failed'),
      );
      final media = _TrackingMediaService(events);

      await expectLater(
        saveRecordWithMedia(
          repository: repository,
          mediaService: media,
          draft: draftWith(const [
            RecordDraftAttachment.picked(
              sourcePath: '/picker/photo.jpg',
              mediaType: MediaType.image,
            ),
          ]),
        ),
        throwsStateError,
      );

      expect(
        events,
        isNot(contains('files:commit:/support/media/originals/0.jpg')),
      );
      expect(events, contains('db:rollback'));
      expect(media.stagingPaths, isEmpty);
      expect(media.finalPaths, isEmpty);
    },
  );

  test('a final SQLite commit failure deletes newly committed files', () async {
    final events = <String>[];
    final repository = _TransactionalRepository(
      events,
      commitError: StateError('disk I/O error'),
    );
    final media = _TrackingMediaService(events);

    await expectLater(
      saveRecordWithMedia(
        repository: repository,
        mediaService: media,
        draft: draftWith(const [
          RecordDraftAttachment.picked(
            sourcePath: '/picker/photo.jpg',
            mediaType: MediaType.image,
          ),
        ]),
      ),
      throwsStateError,
    );

    expect(events, contains('db:commit:failed'));
    expect(
      events.indexOf('files:commit:/support/media/originals/0.jpg'),
      lessThan(events.indexOf('db:commit:failed')),
    );
    expect(media.finalPaths, isEmpty);
    expect(repository.committedInput, isNull);
  });

  test(
    'an update preserves existing attachments alongside committed media',
    () async {
      final events = <String>[];
      final repository = _TransactionalRepository(events);
      final media = _TrackingMediaService(events);

      await saveRecordWithMedia(
        repository: repository,
        mediaService: media,
        recordId: 'record-1',
        draft: draftWith(const [
          RecordDraftAttachment.existing(
            id: 'existing-1',
            mediaType: MediaType.image,
            filePath: '/support/media/originals/existing.jpg',
            thumbnailPath: '/support/media/thumbnails/existing.jpg',
          ),
          RecordDraftAttachment.picked(
            sourcePath: '/picker/new.mov',
            mediaType: MediaType.video,
          ),
        ]),
      );

      expect(repository.committedRecordId, 'record-1');
      expect(repository.committedInput!.attachments, const [
        NewAttachmentInput(
          id: 'existing-1',
          mediaType: MediaType.image,
          filePath: '/support/media/originals/existing.jpg',
          thumbnailPath: '/support/media/thumbnails/existing.jpg',
        ),
        NewAttachmentInput(
          mediaType: MediaType.video,
          filePath: '/support/media/originals/0.mov',
          thumbnailPath: '/support/media/thumbnails/0.jpg',
        ),
      ]);
    },
  );

  test(
    'removed old files are cleaned only after the database commits',
    () async {
      final events = <String>[];
      final repository = _TransactionalRepository(events);
      final media = _TrackingMediaService(events);
      final previous = Attachment(
        id: 'removed-1',
        recordId: 'record-1',
        mediaType: MediaType.image,
        filePath: '/support/media/originals/old.jpg',
        thumbnailPath: '/support/media/thumbnails/old.jpg',
        createdAt: occurredAt,
      );

      await saveRecordWithMedia(
        repository: repository,
        mediaService: media,
        recordId: 'record-1',
        previousAttachments: <Attachment>[previous],
        draft: draftWith(const []),
      );

      final commit = events.indexOf('db:commit');
      final cleanup = events.indexOf(
        'files:remove:/support/media/originals/old.jpg,'
        '/support/media/thumbnails/old.jpg',
      );
      expect(commit, greaterThanOrEqualTo(0));
      expect(cleanup, greaterThan(commit));
    },
  );
}

class _TrackingMediaService implements MediaService {
  _TrackingMediaService(this.events, {this.failStageAt, this.failCommitAt});

  final List<String> events;
  final int? failStageAt;
  final int? failCommitAt;
  final Set<String> stagingPaths = <String>{};
  final Set<String> finalPaths = <String>{};
  var _stageCount = 0;
  var _commitCount = 0;

  @override
  Future<StagedMedia> stage(PickedMedia input) async {
    final index = _stageCount++;
    events.add('files:stage:${input.sourcePath}');
    if (failStageAt == index) throw StateError('stage failed');
    final extension = input.sourcePath.toLowerCase().endsWith('.mov')
        ? 'mov'
        : 'jpg';
    final staged = StagedMedia(
      stagingPath: '/support/staging/$index.$extension',
      finalPath: '/support/media/originals/$index.$extension',
      mediaType: input.mediaType,
      thumbnailStagingPath: '/support/staging/$index-thumb.jpg',
      thumbnailFinalPath: '/support/media/thumbnails/$index.jpg',
    );
    stagingPaths.addAll(<String>[
      staged.stagingPath,
      staged.thumbnailStagingPath!,
    ]);
    return staged;
  }

  @override
  Future<CommittedMedia> commit(StagedMedia staged) async {
    final index = _commitCount++;
    events.add('files:commit:${staged.finalPath}');
    if (failCommitAt == index) throw StateError('commit failed');
    stagingPaths.removeAll(<String>[
      staged.stagingPath,
      staged.thumbnailStagingPath!,
    ]);
    finalPaths.addAll(<String>[staged.finalPath, staged.thumbnailFinalPath!]);
    return CommittedMedia(
      filePath: staged.finalPath,
      thumbnailPath: staged.thumbnailFinalPath,
    );
  }

  @override
  Future<void> rollback(StagedMedia staged) async {
    events.add('files:rollback:${staged.finalPath}');
    stagingPaths.removeAll(<String>[
      staged.stagingPath,
      staged.thumbnailStagingPath!,
    ]);
    finalPaths.removeAll(<String>[
      staged.finalPath,
      staged.thumbnailFinalPath!,
    ]);
  }

  @override
  Future<void> remove(Iterable<String> paths) async {
    final values = paths.toList();
    events.add('files:remove:${values.join(',')}');
    finalPaths.removeAll(values);
  }

  @override
  Future<void> removeOrphans(Set<String> referencedPaths) async {}
}

class _TransactionalRepository implements RecordRepository, RecordTransaction {
  _TransactionalRepository(this.events, {this.writeError, this.commitError});

  final List<String> events;
  final Object? writeError;
  final Object? commitError;
  NewRecordInput? _pendingInput;
  String? _pendingRecordId;
  NewRecordInput? committedInput;
  String? committedRecordId;
  var transactionCount = 0;

  @override
  Future<T> inTransaction<T>(
    Future<T> Function(RecordTransaction transaction) work,
  ) async {
    transactionCount += 1;
    events.add('db:transaction:start');
    try {
      final result = await work(this);
      events.add('db:callback:return');
      if (commitError != null) {
        events.add('db:commit:failed');
        _pendingInput = null;
        _pendingRecordId = null;
        throw commitError!;
      }
      committedInput = _pendingInput;
      committedRecordId = _pendingRecordId;
      events.add('db:commit');
      return result;
    } catch (_) {
      if (events.last != 'db:commit:failed') events.add('db:rollback');
      _pendingInput = null;
      _pendingRecordId = null;
      rethrow;
    }
  }

  @override
  Future<TimelineRecord> create(NewRecordInput input) async {
    events.add('db:create:${input.attachments.firstOrNull?.filePath ?? '-'}');
    if (writeError != null) throw writeError!;
    _pendingInput = input;
    _pendingRecordId = null;
    return _record(input);
  }

  @override
  Future<TimelineRecord> update(String id, NewRecordInput input) async {
    events.add('db:update:$id');
    if (writeError != null) throw writeError!;
    _pendingInput = input;
    _pendingRecordId = id;
    return _record(input);
  }

  TimelineRecord _record(NewRecordInput input) => TimelineRecord(
    id: 'record-1',
    type: input.type,
    occurredAt: input.occurredAt,
    createdAt: DateTime.utc(2026, 8, 1),
    updatedAt: DateTime.utc(2026, 8, 1),
  );

  @override
  Future<List<Attachment>> delete(String id) => throw UnimplementedError();

  @override
  Future<TimelineRecord?> get(String id) async => null;

  @override
  Future<List<TimelineRecord>> list({Set<RecordType> types = const {}}) =>
      throw UnimplementedError();
}
