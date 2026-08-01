import 'package:baby_growth_timeline/domain/date/age_label.dart';
import 'package:baby_growth_timeline/domain/date/timeline_grouping.dart';
import 'package:baby_growth_timeline/domain/models/attachment.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calculates age using natural calendar months', () {
    expect(
      calculateAgeLabel(DateTime(2025, 6, 15), DateTime(2026, 8, 1)),
      '1岁1个月',
    );
    expect(
      calculateAgeLabel(DateTime(2026, 7, 15), DateTime(2026, 8, 1)),
      '17天',
    );
  });

  test(
    'groups newest local day first and keeps UTC-descending order in a day',
    () {
      final records = [
        _record('old', DateTime.utc(2026, 7, 31, 8)),
        _record('newer', DateTime.utc(2026, 8, 1, 3)),
        _record('newest', DateTime.utc(2026, 8, 1, 4)),
      ];

      final groups = groupRecordsByLocalDay(records);

      expect(groups.map((group) => group.key), ['2026-08-01', '2026-07-31']);
      expect(groups.first.records.map((record) => record.id), [
        'newest',
        'newer',
      ]);
    },
  );

  test('uses local time when deriving a day key', () {
    final utc = DateTime.utc(2026, 8, 1, 16, 30);

    final expected = utc.toLocal();
    expect(
      localDayKey(utc),
      '${expected.year.toString().padLeft(4, '0')}-'
      '${expected.month.toString().padLeft(2, '0')}-'
      '${expected.day.toString().padLeft(2, '0')}',
    );
  });
}

TimelineRecord _record(String id, DateTime occurredAt) => TimelineRecord(
  id: id,
  type: RecordType.moment,
  occurredAt: occurredAt,
  attachments: const <Attachment>[],
  createdAt: occurredAt,
  updatedAt: occurredAt,
);
