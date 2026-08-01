// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attachment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Attachment _$AttachmentFromJson(Map<String, dynamic> json) => _Attachment(
  id: json['id'] as String,
  recordId: json['recordId'] as String,
  mediaType: $enumDecode(_$MediaTypeEnumMap, json['mediaType']),
  filePath: json['filePath'] as String,
  thumbnailPath: json['thumbnailPath'] as String?,
  createdAt: const UtcDateTimeConverter().fromJson(json['createdAt'] as String),
);

Map<String, dynamic> _$AttachmentToJson(_Attachment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'recordId': instance.recordId,
      'mediaType': _$MediaTypeEnumMap[instance.mediaType]!,
      'filePath': instance.filePath,
      'thumbnailPath': instance.thumbnailPath,
      'createdAt': const UtcDateTimeConverter().toJson(instance.createdAt),
    };

const _$MediaTypeEnumMap = {MediaType.image: 'image', MediaType.video: 'video'};

_NewAttachmentInput _$NewAttachmentInputFromJson(Map<String, dynamic> json) =>
    _NewAttachmentInput(
      id: json['id'] as String?,
      mediaType: $enumDecode(_$MediaTypeEnumMap, json['mediaType']),
      filePath: json['filePath'] as String,
      thumbnailPath: json['thumbnailPath'] as String?,
    );

Map<String, dynamic> _$NewAttachmentInputToJson(_NewAttachmentInput instance) =>
    <String, dynamic>{
      'id': instance.id,
      'mediaType': _$MediaTypeEnumMap[instance.mediaType]!,
      'filePath': instance.filePath,
      'thumbnailPath': instance.thumbnailPath,
    };
