import 'package:freezed_annotation/freezed_annotation.dart';

import 'utc_date_time_converter.dart';

part 'attachment.freezed.dart';
part 'attachment.g.dart';

enum MediaType { image, video }

@freezed
abstract class Attachment with _$Attachment {
  const factory Attachment({
    required String id,
    required String recordId,
    required MediaType mediaType,
    required String filePath,
    String? thumbnailPath,
    @UtcDateTimeConverter() required DateTime createdAt,
  }) = _Attachment;

  factory Attachment.fromJson(Map<String, dynamic> json) =>
      _$AttachmentFromJson(json);
}

@freezed
abstract class NewAttachmentInput with _$NewAttachmentInput {
  const factory NewAttachmentInput({
    String? id,
    required MediaType mediaType,
    required String filePath,
    String? thumbnailPath,
  }) = _NewAttachmentInput;

  factory NewAttachmentInput.fromJson(Map<String, dynamic> json) =>
      _$NewAttachmentInputFromJson(json);
}
