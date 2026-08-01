// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'baby.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Baby _$BabyFromJson(Map<String, dynamic> json) => _Baby(
  id: json['id'] as String,
  name: json['name'] as String,
  birthDate: json['birthDate'] as String,
  sex: json['sex'] as String?,
  avatarPath: json['avatarPath'] as String?,
  createdAt: const UtcDateTimeConverter().fromJson(json['createdAt'] as String),
  updatedAt: const UtcDateTimeConverter().fromJson(json['updatedAt'] as String),
);

Map<String, dynamic> _$BabyToJson(_Baby instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'birthDate': instance.birthDate,
  'sex': instance.sex,
  'avatarPath': instance.avatarPath,
  'createdAt': const UtcDateTimeConverter().toJson(instance.createdAt),
  'updatedAt': const UtcDateTimeConverter().toJson(instance.updatedAt),
};

_BabyDraft _$BabyDraftFromJson(Map<String, dynamic> json) => _BabyDraft(
  name: json['name'] as String,
  birthDate: json['birthDate'] as String,
  sex: json['sex'] as String?,
  avatarPath: json['avatarPath'] as String?,
);

Map<String, dynamic> _$BabyDraftToJson(_BabyDraft instance) =>
    <String, dynamic>{
      'name': instance.name,
      'birthDate': instance.birthDate,
      'sex': instance.sex,
      'avatarPath': instance.avatarPath,
    };
