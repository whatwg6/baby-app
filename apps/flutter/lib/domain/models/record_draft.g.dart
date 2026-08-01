// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'record_draft.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PickedAttachment _$PickedAttachmentFromJson(Map<String, dynamic> json) =>
    PickedAttachment(
      sourcePath: json['sourcePath'] as String,
      mediaType: $enumDecode(_$MediaTypeEnumMap, json['mediaType']),
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$PickedAttachmentToJson(PickedAttachment instance) =>
    <String, dynamic>{
      'sourcePath': instance.sourcePath,
      'mediaType': _$MediaTypeEnumMap[instance.mediaType]!,
      'runtimeType': instance.$type,
    };

const _$MediaTypeEnumMap = {MediaType.image: 'image', MediaType.video: 'video'};

ExistingAttachment _$ExistingAttachmentFromJson(Map<String, dynamic> json) =>
    ExistingAttachment(
      id: json['id'] as String,
      mediaType: $enumDecode(_$MediaTypeEnumMap, json['mediaType']),
      filePath: json['filePath'] as String,
      thumbnailPath: json['thumbnailPath'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$ExistingAttachmentToJson(ExistingAttachment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'mediaType': _$MediaTypeEnumMap[instance.mediaType]!,
      'filePath': instance.filePath,
      'thumbnailPath': instance.thumbnailPath,
      'runtimeType': instance.$type,
    };

_RecordDraft _$RecordDraftFromJson(Map<String, dynamic> json) => _RecordDraft(
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
          ?.map(
            (e) => RecordDraftAttachment.fromJson(e as Map<String, dynamic>),
          )
          .toList() ??
      const <RecordDraftAttachment>[],
);

Map<String, dynamic> _$RecordDraftToJson(_RecordDraft instance) =>
    <String, dynamic>{
      'type': _$RecordTypeEnumMap[instance.type]!,
      'occurredAt': const UtcDateTimeConverter().toJson(instance.occurredAt),
      'note': instance.note,
      'details': instance.details,
      'attachments': instance.attachments,
    };

const _$RecordTypeEnumMap = {
  RecordType.moment: 'moment',
  RecordType.growth: 'growth',
  RecordType.activity: 'activity',
  RecordType.milestone: 'milestone',
};

_NewRecordInput _$NewRecordInputFromJson(Map<String, dynamic> json) =>
    _NewRecordInput(
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
              ?.map(
                (e) => NewAttachmentInput.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const <NewAttachmentInput>[],
    );

Map<String, dynamic> _$NewRecordInputToJson(_NewRecordInput instance) =>
    <String, dynamic>{
      'type': _$RecordTypeEnumMap[instance.type]!,
      'occurredAt': const UtcDateTimeConverter().toJson(instance.occurredAt),
      'note': instance.note,
      'details': instance.details,
      'attachments': instance.attachments,
    };
