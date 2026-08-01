import 'package:freezed_annotation/freezed_annotation.dart';

import 'utc_date_time_converter.dart';

part 'baby.freezed.dart';
part 'baby.g.dart';

@freezed
abstract class Baby with _$Baby {
  const factory Baby({
    required String id,
    required String name,
    required String birthDate,
    String? sex,
    String? avatarPath,
    @UtcDateTimeConverter() required DateTime createdAt,
    @UtcDateTimeConverter() required DateTime updatedAt,
  }) = _Baby;

  factory Baby.fromJson(Map<String, dynamic> json) => _$BabyFromJson(json);
}

@freezed
abstract class BabyDraft with _$BabyDraft {
  const factory BabyDraft({
    required String name,
    required String birthDate,
    String? sex,
    String? avatarPath,
  }) = _BabyDraft;

  factory BabyDraft.fromJson(Map<String, dynamic> json) =>
      _$BabyDraftFromJson(json);
}
