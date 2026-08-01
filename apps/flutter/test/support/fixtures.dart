import 'package:baby_growth_timeline/domain/models/attachment.dart';
import 'package:baby_growth_timeline/domain/models/baby.dart';
import 'package:baby_growth_timeline/domain/models/record_draft.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';

final fixtureOccurredAt = DateTime.parse('2026-07-31T22:15:00+08:00');

BabyDraft babyDraftFixture({String name = '宝宝'}) => BabyDraft(
  name: name,
  birthDate: '2025-06-12',
  sex: '女',
  avatarPath: '/avatars/baby.jpg',
);

NewRecordInput momentInputFixture({
  String? note = '第一次微笑',
  DateTime? occurredAt,
  List<NewAttachmentInput>? attachments,
}) => NewRecordInput(
  type: RecordType.moment,
  occurredAt: occurredAt ?? fixtureOccurredAt,
  note: note,
  attachments:
      attachments ??
      const [
        NewAttachmentInput(
          id: 'attachment-moment',
          mediaType: MediaType.image,
          filePath: '/media/smile.jpg',
          thumbnailPath: '/media/smile-thumb.jpg',
        ),
      ],
);

NewRecordInput growthInputFixture({DateTime? occurredAt}) => NewRecordInput(
  type: RecordType.growth,
  occurredAt: occurredAt ?? fixtureOccurredAt,
  note: '满六个月',
  details: const RecordDetails.growth(
    heightCm: 68.5,
    weightKg: 7.4,
    headCm: 42.1,
  ),
);

NewRecordInput activityInputFixture({DateTime? occurredAt}) => NewRecordInput(
  type: RecordType.activity,
  occurredAt: occurredAt ?? fixtureOccurredAt,
  note: '午觉',
  details: const RecordDetails.activity(
    activityType: ActivityType.sleep,
    amount: 120,
    durationMinutes: 95,
  ),
);

NewRecordInput milestoneInputFixture({DateTime? occurredAt}) => NewRecordInput(
  type: RecordType.milestone,
  occurredAt: occurredAt ?? fixtureOccurredAt,
  note: '值得纪念',
  details: const RecordDetails.milestone(
    title: '第一次独站',
    presetKey: 'stand-alone',
  ),
);
