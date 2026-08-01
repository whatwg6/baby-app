import 'package:freezed_annotation/freezed_annotation.dart';

import 'attachment.dart';
import 'utc_date_time_converter.dart';

part 'timeline_record.freezed.dart';
part 'timeline_record.g.dart';

enum RecordType { moment, growth, activity, milestone }

enum ActivityType { feeding, sleep, diaper }

@freezed
sealed class RecordDetails with _$RecordDetails {
  const factory RecordDetails.growth({
    double? heightCm,
    double? weightKg,
    double? headCm,
  }) = GrowthDetails;

  const factory RecordDetails.activity({
    required ActivityType activityType,
    double? amount,
    int? durationMinutes,
  }) = ActivityDetails;

  const factory RecordDetails.milestone({
    required String title,
    String? presetKey,
  }) = MilestoneDetails;

  factory RecordDetails.fromJson(Map<String, dynamic> json) =>
      _$RecordDetailsFromJson(json);
}

/// A persisted record. [occurredAt] is always an UTC instant in the domain.
@freezed
abstract class TimelineRecord with _$TimelineRecord {
  const factory TimelineRecord({
    required String id,
    required RecordType type,
    @UtcDateTimeConverter() required DateTime occurredAt,
    String? note,
    RecordDetails? details,
    @Default(<Attachment>[]) List<Attachment> attachments,
    @UtcDateTimeConverter() required DateTime createdAt,
    @UtcDateTimeConverter() required DateTime updatedAt,
  }) = _TimelineRecord;

  factory TimelineRecord.fromJson(Map<String, dynamic> json) =>
      _$TimelineRecordFromJson(json);
}
