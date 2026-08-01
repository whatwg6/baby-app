// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_manifest.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_BackupManifestV1 _$BackupManifestV1FromJson(Map<String, dynamic> json) =>
    _BackupManifestV1(
      format: json['format'] as String? ?? 'baby-growth-backup',
      version: (json['version'] as num?)?.toInt() ?? 1,
      createdAt: json['createdAt'] as String,
      database: BackupFileEntry.fromJson(
        json['database'] as Map<String, dynamic>,
      ),
      media: (json['media'] as List<dynamic>)
          .map((e) => BackupFileEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$BackupManifestV1ToJson(_BackupManifestV1 instance) =>
    <String, dynamic>{
      'format': instance.format,
      'version': instance.version,
      'createdAt': instance.createdAt,
      'database': instance.database,
      'media': instance.media,
    };

_BackupFileEntry _$BackupFileEntryFromJson(Map<String, dynamic> json) =>
    _BackupFileEntry(
      path: json['path'] as String,
      sha256: json['sha256'] as String,
      size: (json['size'] as num).toInt(),
    );

Map<String, dynamic> _$BackupFileEntryToJson(_BackupFileEntry instance) =>
    <String, dynamic>{
      'path': instance.path,
      'sha256': instance.sha256,
      'size': instance.size,
    };
