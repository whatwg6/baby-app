import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../models/baby.dart';

/// Validates a profile draft against local-calendar birthday rules.
BabyDraft validateBabyDraft(BabyDraft draft, {DateTime? now}) {
  if (draft.name.trim().isEmpty) {
    throw const ValidationException('请输入宝宝姓名。', field: 'name');
  }

  final birthDate = _parseBirthDate(draft.birthDate);
  final reference = (now ?? DateTime.now()).toLocal();
  final today = DateTime(reference.year, reference.month, reference.day);
  if (birthDate.isAfter(today)) {
    throw const ValidationException('生日不能晚于今天。', field: 'birthDate');
  }

  return draft;
}

DateTime _parseBirthDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const ValidationException('生日格式应为 yyyy-MM-dd。', field: 'birthDate');
  }

  try {
    return DateFormat('yyyy-MM-dd').parseStrict(value);
  } on FormatException {
    throw const ValidationException('请输入有效的生日。', field: 'birthDate');
  }
}
