import 'package:baby_growth_timeline/data/repositories/baby_repository.dart';
import 'package:baby_growth_timeline/data/repositories/record_repository.dart';
import 'package:baby_growth_timeline/domain/models/attachment.dart';
import 'package:baby_growth_timeline/domain/models/record_draft.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void babyRepositoryContract(Future<BabyRepository> Function() create) {
  test('creates, reads, updates and deletes a baby', () async {
    final repository = await create();

    final created = await repository.create(babyDraftFixture());
    expect(await repository.get(created.id), created);

    final updated = await repository.update(
      created.id,
      babyDraftFixture(name: '小糖'),
    );
    expect(updated.name, '小糖');
    expect(updated.createdAt, created.createdAt);
    expect(updated.updatedAt.isBefore(created.updatedAt), isFalse);

    await repository.delete(created.id);
    expect(await repository.get(created.id), isNull);
  });

  test('returns the current baby and rejects a second profile', () async {
    final repository = await create();
    final first = await repository.create(babyDraftFixture());

    expect(await repository.getCurrent(), first);
    await expectLater(
      repository.create(babyDraftFixture(name: '小糖')),
      throwsStateError,
    );
    expect(await repository.getCurrent(), first);
  });
}

void recordRepositoryContract(Future<RecordRepository> Function() create) {
  test('creates, lists, updates and deletes a complete record', () async {
    final repository = await create();
    final created = await repository.create(momentInputFixture());
    expect((await repository.list()).single, created);

    await repository.update(created.id, momentInputFixture(note: '修改后'));
    expect((await repository.get(created.id))?.note, '修改后');

    final removed = await repository.delete(created.id);
    expect(removed, isNotEmpty);
    expect(await repository.get(created.id), isNull);
  });

  test('maps every record detail variant and attachments', () async {
    final repository = await create();
    final moment = await repository.create(momentInputFixture());
    final growth = await repository.create(growthInputFixture());
    final activity = await repository.create(activityInputFixture());
    final milestone = await repository.create(milestoneInputFixture());

    expect((await repository.get(moment.id))?.attachments, moment.attachments);
    expect((await repository.get(growth.id))?.details, isA<GrowthDetails>());
    expect((await repository.get(growth.id))?.details, growth.details);
    expect((await repository.get(activity.id))?.details, activity.details);
    expect((await repository.get(milestone.id))?.details, milestone.details);
  });

  test('filters by type and lists newest occurrence first', () async {
    final repository = await create();
    final oldMoment = await repository.create(
      momentInputFixture(
        occurredAt: DateTime.utc(2026, 1, 1),
        attachments: const [],
      ),
    );
    final newestGrowth = await repository.create(
      growthInputFixture(occurredAt: DateTime.utc(2026, 3, 1)),
    );
    final middleMoment = await repository.create(
      momentInputFixture(
        occurredAt: DateTime.utc(2026, 2, 1),
        attachments: const [],
      ),
    );

    expect((await repository.list()).map((record) => record.id), [
      newestGrowth.id,
      middleMoment.id,
      oldMoment.id,
    ]);
    expect(
      (await repository.list(
        types: {RecordType.moment},
      )).map((record) => record.id),
      [middleMoment.id, oldMoment.id],
    );
  });

  test('transaction adapter is non-nested and rolls back all writes', () async {
    final repository = await create();

    await expectLater(
      repository.inTransaction<void>((transaction) async {
        await transaction.create(momentInputFixture());
        await transaction.create(growthInputFixture());
        throw StateError('rollback');
      }),
      throwsStateError,
    );

    expect(await repository.list(), isEmpty);
  });

  test('update rebuilds details and synchronizes attachment indexes', () async {
    final repository = await create();
    final created = await repository.create(growthInputFixture());

    final updated = await repository.update(
      created.id,
      NewRecordInput(
        type: RecordType.milestone,
        occurredAt: fixtureOccurredAt,
        details: const RecordDetails.milestone(title: '会走路了'),
        attachments: const [
          NewAttachmentInput(
            id: 'replacement-video',
            mediaType: MediaType.video,
            filePath: '/media/walk.mp4',
            thumbnailPath: '/media/walk.jpg',
          ),
        ],
      ),
    );

    expect(updated.type, RecordType.milestone);
    expect(updated.details, const RecordDetails.milestone(title: '会走路了'));
    expect(updated.attachments.single.id, 'replacement-video');
  });
}
