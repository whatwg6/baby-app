import 'package:freezed_annotation/freezed_annotation.dart';

part 'backup_manifest.freezed.dart';
part 'backup_manifest.g.dart';

@freezed
abstract class BackupManifestV1 with _$BackupManifestV1 {
  const factory BackupManifestV1({
    @Default('baby-growth-backup') String format,
    @Default(1) int version,
    required String createdAt,
    required BackupFileEntry database,
    required List<BackupFileEntry> media,
  }) = _BackupManifestV1;

  factory BackupManifestV1.fromJson(Map<String, dynamic> json) =>
      _$BackupManifestV1FromJson(json);
}

@freezed
abstract class BackupFileEntry with _$BackupFileEntry {
  const factory BackupFileEntry({
    required String path,
    required String sha256,
    required int size,
  }) = _BackupFileEntry;

  factory BackupFileEntry.fromJson(Map<String, dynamic> json) =>
      _$BackupFileEntryFromJson(json);
}
