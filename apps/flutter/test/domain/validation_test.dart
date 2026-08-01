import 'package:baby_growth_timeline/core/errors/app_exception.dart';
import 'package:baby_growth_timeline/domain/models/baby.dart';
import 'package:baby_growth_timeline/domain/models/record_draft.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';
import 'package:baby_growth_timeline/domain/validation/baby_validator.dart';
import 'package:baby_growth_timeline/domain/validation/record_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateBabyDraft', () {
    test('rejects a future birthday', () {
      expect(
        () => validateBabyDraft(
          const BabyDraft(name: '安安', birthDate: '2099-01-01'),
          now: DateTime(2026, 8, 1),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects a name that is empty after trimming', () {
      expect(
        () => validateBabyDraft(
          const BabyDraft(name: '  ', birthDate: '2025-06-15'),
          now: DateTime(2026, 8, 1),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects birthday text that is not an exact calendar date', () {
      expect(
        () => validateBabyDraft(
          const BabyDraft(name: '安安', birthDate: '2025-02-30'),
          now: DateTime(2026, 8, 1),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('accepts a valid birthday in the required format', () {
      const draft = BabyDraft(name: '安安', birthDate: '2025-06-15');

      expect(validateBabyDraft(draft, now: DateTime(2026, 8, 1)), draft);
    });
  });

  group('validateRecordDraft', () {
    test('rejects an empty growth record', () {
      expect(
        () => validateRecordDraft(
          RecordDraft.growth(occurredAt: DateTime(2026, 8, 1)),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('requires text or media for a moment', () {
      expect(
        () => validateRecordDraft(
          RecordDraft(
            type: RecordType.moment,
            occurredAt: DateTime(2026, 8, 1),
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('accepts one in-range growth measurement', () {
      final draft = RecordDraft.growth(
        occurredAt: DateTime(2026, 8, 1),
        weightKg: 8.4,
      );

      expect(validateRecordDraft(draft), draft);
    });

    test('rejects clearly mistyped growth measurements', () {
      final draft = RecordDraft.growth(
        occurredAt: DateTime(2026, 8, 1),
        heightCm: 19.9,
      );

      expect(
        () => validateRecordDraft(draft),
        throwsA(isA<ValidationException>()),
      );
    });

    test('requires a nonblank milestone title', () {
      final draft = RecordDraft(
        type: RecordType.milestone,
        occurredAt: DateTime(2026, 8, 1),
        details: const RecordDetails.milestone(title: '  '),
      );

      expect(
        () => validateRecordDraft(draft),
        throwsA(isA<ValidationException>()),
      );
    });

    test('accepts activity boundaries and rejects values outside them', () {
      final valid = RecordDraft(
        type: RecordType.activity,
        occurredAt: DateTime(2026, 8, 1),
        details: const RecordDetails.activity(
          activityType: ActivityType.feeding,
          amount: 0.1,
          durationMinutes: 1440,
        ),
      );
      final invalid = valid.copyWith(
        details: const RecordDetails.activity(
          activityType: ActivityType.sleep,
          durationMinutes: 1441,
        ),
      );

      expect(validateRecordDraft(valid), valid);
      expect(
        () => validateRecordDraft(invalid),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
