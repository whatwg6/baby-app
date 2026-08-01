import 'package:flutter/foundation.dart';

import '../../../data/repositories/record_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../domain/models/attachment.dart';
import '../../../domain/models/record_draft.dart';
import '../../../domain/models/timeline_record.dart';
import '../../../domain/validation/record_validator.dart';
import '../../media/application/save_record_with_media.dart';
import '../../media/data/local_media_service.dart';
import '../../media/domain/media_service.dart';

/// Owns a record draft and persists it once the editor has validated it.
class RecordEditorController extends ChangeNotifier {
  RecordEditorController(
    this._repository, {
    required RecordType type,
    this.recordId,
    DateTime Function()? now,
    MediaService? mediaService,
  }) : _draft = RecordDraft(type: type, occurredAt: (now ?? DateTime.now)()),
       _mediaService = mediaService ?? LocalMediaService(),
       _isLoading = recordId != null;

  final RecordRepository _repository;
  final MediaService _mediaService;
  final String? recordId;

  RecordDraft _draft;
  RecordDraft get draft => _draft;
  bool _isLoading;
  bool get isLoading => _isLoading;
  bool _isSaving = false;
  bool get isSaving => _isSaving;
  String? _validationError;
  String? get validationError => _validationError;
  String? _saveError;
  String? get saveError => _saveError;
  TimelineRecord? _record;
  TimelineRecord? get record => _record;

  Future<void> load() async {
    final id = recordId;
    if (id == null) return;
    _isLoading = true;
    _saveError = null;
    notifyListeners();
    try {
      final record = await _repository.get(id);
      if (record == null) {
        _saveError = '记录不存在';
        return;
      }
      _record = record;
      _draft = RecordDraft(
        type: record.type,
        occurredAt: record.occurredAt.toLocal(),
        note: record.note,
        details: record.details,
        attachments: record.attachments
            .map(
              (attachment) => RecordDraftAttachment.existing(
                id: attachment.id,
                mediaType: attachment.mediaType,
                filePath: attachment.filePath,
                thumbnailPath: attachment.thumbnailPath,
              ),
            )
            .toList(),
      );
    } catch (_) {
      _saveError = '无法读取记录，请重试';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updateDraft(RecordDraft value) {
    _draft = value;
    _validationError = null;
    notifyListeners();
  }

  Future<TimelineRecord?> submit() async {
    if (_isSaving) return null;
    _validationError = null;
    _saveError = null;
    try {
      validateRecordDraft(_draft);
    } on ValidationException catch (error) {
      _validationError = error.message;
      notifyListeners();
      return null;
    }

    _isSaving = true;
    notifyListeners();
    try {
      final saved = await saveRecordWithMedia(
        repository: _repository,
        mediaService: _mediaService,
        draft: _draft,
        recordId: recordId,
        previousAttachments: _record?.attachments ?? const <Attachment>[],
      );
      _record = saved;
      return saved;
    } catch (_) {
      _saveError = '保存失败，已有数据未受影响';
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
