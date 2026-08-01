// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GrowthDetails _$GrowthDetailsFromJson(Map<String, dynamic> json) =>
    GrowthDetails(
      heightCm: (json['heightCm'] as num?)?.toDouble(),
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      headCm: (json['headCm'] as num?)?.toDouble(),
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$GrowthDetailsToJson(GrowthDetails instance) =>
    <String, dynamic>{
      'heightCm': instance.heightCm,
      'weightKg': instance.weightKg,
      'headCm': instance.headCm,
      'runtimeType': instance.$type,
    };

ActivityDetails _$ActivityDetailsFromJson(Map<String, dynamic> json) =>
    ActivityDetails(
      activityType: $enumDecode(_$ActivityTypeEnumMap, json['activityType']),
      amount: (json['amount'] as num?)?.toDouble(),
      durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$ActivityDetailsToJson(ActivityDetails instance) =>
    <String, dynamic>{
      'activityType': _$ActivityTypeEnumMap[instance.activityType]!,
      'amount': instance.amount,
      'durationMinutes': instance.durationMinutes,
      'runtimeType': instance.$type,
    };

const _$ActivityTypeEnumMap = {
  ActivityType.feeding: 'feeding',
  ActivityType.sleep: 'sleep',
  ActivityType.diaper: 'diaper',
};

MilestoneDetails _$MilestoneDetailsFromJson(Map<String, dynamic> json) =>
    MilestoneDetails(
      title: json['title'] as String,
      presetKey: json['presetKey'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$MilestoneDetailsToJson(MilestoneDetails instance) =>
    <String, dynamic>{
      'title': instance.title,
      'presetKey': instance.presetKey,
      'runtimeType': instance.$type,
    };

_TimelineRecord _$TimelineRecordFromJson(
  Map<String, dynamic> json,
) => _TimelineRecord(
  id: json['id'] as String,
  type: $enumDecode(_$RecordTypeEnumMap, json['type']),
  occurredAt: const UtcDateTimeConverter().fromJson(
    json['occurredAt'] as String,
  ),
  note: json['note'] as String?,
  details: json['details'] == null
      ? null
      : RecordDetails.fromJson(json['details'] as Map<String, dynamic>),
  attachments:
      (json['attachments'] as List<dynamic>?)
          ?.map((e) => Attachment.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <Attachment>[],
  createdAt: const UtcDateTimeConverter().fromJson(json['createdAt'] as String),
  updatedAt: const UtcDateTimeConverter().fromJson(json['updatedAt'] as String),
);

Map<String, dynamic> _$TimelineRecordToJson(_TimelineRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': _$RecordTypeEnumMap[instance.type]!,
      'occurredAt': const UtcDateTimeConverter().toJson(instance.occurredAt),
      'note': instance.note,
      'details': instance.details,
      'attachments': instance.attachments,
      'createdAt': const UtcDateTimeConverter().toJson(instance.createdAt),
      'updatedAt': const UtcDateTimeConverter().toJson(instance.updatedAt),
    };

const _$RecordTypeEnumMap = {
  RecordType.moment: 'moment',
  RecordType.growth: 'growth',
  RecordType.activity: 'activity',
  RecordType.milestone: 'milestone',
};
