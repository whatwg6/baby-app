import 'package:freezed_annotation/freezed_annotation.dart';

import 'attachment.dart';
import 'timeline_record.dart';
import 'utc_date_time_converter.dart';

part 'record_draft.freezed.dart';
part 'record_draft.g.dart';

@freezed
sealed class RecordDraftAttachment with _$RecordDraftAttachment {
  const factory RecordDraftAttachment.picked({
    required String sourcePath,
    required MediaType mediaType,
  }) = PickedAttachment;

  const factory RecordDraftAttachment.existing({
    required String id,
    required MediaType mediaType,
    required String filePath,
    String? thumbnailPath,
  }) = ExistingAttachment;

  factory RecordDraftAttachment.fromJson(Map<String, dynamic> json) =>
      _$RecordDraftAttachmentFromJson(json);
}

@freezed
abstract class RecordDraft with _$RecordDraft {
  const RecordDraft._();

  const factory RecordDraft({
    required RecordType type,
    @UtcDateTimeConverter() required DateTime occurredAt,
    String? note,
    RecordDetails? details,
    @Default(<RecordDraftAttachment>[]) List<RecordDraftAttachment> attachments,
  }) = _RecordDraft;

  /// Convenience constructor for the growth form.
  factory RecordDraft.growth({
    required DateTime occurredAt,
    String? note,
    double? heightCm,
    double? weightKg,
    double? headCm,
    List<RecordDraftAttachment> attachments = const <RecordDraftAttachment>[],
  }) => RecordDraft(
    type: RecordType.growth,
    occurredAt: occurredAt,
    note: note,
    details: RecordDetails.growth(
      heightCm: heightCm,
      weightKg: weightKg,
      headCm: headCm,
    ),
    attachments: attachments,
  );

  factory RecordDraft.fromJson(Map<String, dynamic> json) =>
      _$RecordDraftFromJson(json);
}

@freezed
abstract class NewRecordInput with _$NewRecordInput {
  const factory NewRecordInput({
    required RecordType type,
    @UtcDateTimeConverter() required DateTime occurredAt,
    String? note,
    RecordDetails? details,
    @Default(<NewAttachmentInput>[]) List<NewAttachmentInput> attachments,
  }) = _NewRecordInput;

  factory NewRecordInput.fromJson(Map<String, dynamic> json) =>
      _$NewRecordInputFromJson(json);
}
