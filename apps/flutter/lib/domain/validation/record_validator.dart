import '../../core/errors/app_exception.dart';
import '../models/record_draft.dart';
import '../models/timeline_record.dart';

/// Validates the shared and type-specific fields of a timeline record draft.
RecordDraft validateRecordDraft(RecordDraft draft) {
  switch (draft.type) {
    case RecordType.moment:
      _validateMoment(draft);
    case RecordType.growth:
      _validateGrowth(draft);
    case RecordType.activity:
      _validateActivity(draft);
    case RecordType.milestone:
      _validateMilestone(draft);
  }

  return draft;
}

void _validateMoment(RecordDraft draft) {
  if ((draft.note?.trim().isEmpty ?? true) && draft.attachments.isEmpty) {
    throw const ValidationException('珍贵时刻请填写文字或添加媒体。', field: 'note');
  }
}

void _validateGrowth(RecordDraft draft) {
  final details = draft.details;
  if (details is! GrowthDetails) {
    throw const ValidationException('请填写至少一项成长数据。', field: 'details');
  }

  if (details.heightCm == null &&
      details.weightKg == null &&
      details.headCm == null) {
    throw const ValidationException('请填写至少一项成长数据。', field: 'details');
  }

  _validateRange(
    details.heightCm,
    minimum: 20,
    maximum: 250,
    field: 'heightCm',
    message: '身高请填写 20–250 cm 之间的数值。',
  );
  _validateRange(
    details.weightKg,
    minimum: 0.2,
    maximum: 300,
    field: 'weightKg',
    message: '体重请填写 0.2–300 kg 之间的数值。',
  );
  _validateRange(
    details.headCm,
    minimum: 10,
    maximum: 100,
    field: 'headCm',
    message: '头围请填写 10–100 cm 之间的数值。',
  );
}

void _validateActivity(RecordDraft draft) {
  final details = draft.details;
  if (details is! ActivityDetails) {
    throw const ValidationException('请选择活动类型。', field: 'activityType');
  }

  final amount = details.amount;
  if (amount != null && (!amount.isFinite || amount <= 0)) {
    throw const ValidationException('数量请填写大于 0 的数值。', field: 'amount');
  }

  final duration = details.durationMinutes;
  if (duration != null && (duration < 1 || duration > 1440)) {
    throw const ValidationException(
      '时长请填写 1–1440 分钟。',
      field: 'durationMinutes',
    );
  }
}

void _validateMilestone(RecordDraft draft) {
  final details = draft.details;
  if (details is! MilestoneDetails || details.title.trim().isEmpty) {
    throw const ValidationException('请输入里程碑标题。', field: 'title');
  }
}

void _validateRange(
  double? value, {
  required double minimum,
  required double maximum,
  required String field,
  required String message,
}) {
  if (value != null &&
      (!value.isFinite || value < minimum || value > maximum)) {
    throw ValidationException(message, field: field);
  }
}
