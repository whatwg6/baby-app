import 'package:baby_growth_timeline/domain/models/attachment.dart';
import 'package:baby_growth_timeline/domain/models/baby.dart';
import 'package:baby_growth_timeline/domain/models/record_draft.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'TimelineRecord round-trips local timestamps as UTC ISO-8601 instants',
    () {
      final local = _localInstant();
      final record = TimelineRecord(
        id: 'record-1',
        type: RecordType.moment,
        occurredAt: local,
        attachments: const <Attachment>[],
        createdAt: local,
        updatedAt: local,
      );

      final json = record.toJson();
      final restored = TimelineRecord.fromJson(json);

      expect(json['occurredAt'], '2026-08-01T01:30:00.000Z');
      expect(json['createdAt'], '2026-08-01T01:30:00.000Z');
      expect(json['updatedAt'], '2026-08-01T01:30:00.000Z');
      expect(restored.occurredAt, DateTime.utc(2026, 8, 1, 1, 30));
      expect(restored.occurredAt.isUtc, isTrue);
      expect(restored.createdAt.isUtc, isTrue);
      expect(restored.updatedAt.isUtc, isTrue);
    },
  );

  test('RecordDraft round-trips a local occurrence time as UTC', () {
    final draft = RecordDraft(
      type: RecordType.moment,
      occurredAt: _localInstant(),
    );

    final json = draft.toJson();
    final restored = RecordDraft.fromJson(json);

    expect(json['occurredAt'], '2026-08-01T01:30:00.000Z');
    expect(restored.occurredAt, DateTime.utc(2026, 8, 1, 1, 30));
    expect(restored.occurredAt.isUtc, isTrue);
  });

  test('NewRecordInput round-trips a local occurrence time as UTC', () {
    final input = NewRecordInput(
      type: RecordType.activity,
      occurredAt: _localInstant(),
    );

    final json = input.toJson();
    final restored = NewRecordInput.fromJson(json);

    expect(json['occurredAt'], '2026-08-01T01:30:00.000Z');
    expect(restored.occurredAt, DateTime.utc(2026, 8, 1, 1, 30));
    expect(restored.occurredAt.isUtc, isTrue);
  });

  test('Baby metadata round-trips local timestamps as UTC', () {
    final baby = Baby(
      id: 'baby-1',
      name: '安安',
      birthDate: '2025-06-15',
      createdAt: _localInstant(),
      updatedAt: _localInstant(),
    );

    final json = baby.toJson();
    final restored = Baby.fromJson(json);

    expect(json['createdAt'], '2026-08-01T01:30:00.000Z');
    expect(json['updatedAt'], '2026-08-01T01:30:00.000Z');
    expect(restored.createdAt.isUtc, isTrue);
    expect(restored.updatedAt.isUtc, isTrue);
  });
}

DateTime _localInstant() =>
    DateTime.parse('2026-08-01T09:30:00+08:00').toLocal();
