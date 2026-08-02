import 'dart:io';

import 'package:baby_growth_timeline/domain/date/timeline_grouping.dart';
import 'package:baby_growth_timeline/domain/models/attachment.dart';
import 'package:baby_growth_timeline/domain/models/timeline_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final timezone = Platform.environment['TZ'];
  final proof = switch (timezone) {
    'UTC' => _TimezoneProof(
      localDay: '2026-08-01',
      olderUtc: DateTime.utc(2026, 8, 1, 23, 30),
      newerUtc: DateTime.utc(2026, 8, 2, 0, 30),
      groupedDays: const ['2026-08-02', '2026-08-01'],
    ),
    'Asia/Shanghai' => _TimezoneProof(
      localDay: '2026-08-02',
      olderUtc: DateTime.utc(2026, 8, 1, 15, 30),
      newerUtc: DateTime.utc(2026, 8, 1, 16, 30),
      groupedDays: const ['2026-08-02', '2026-08-01'],
    ),
    'America/Los_Angeles' => _TimezoneProof(
      localDay: '2026-08-01',
      olderUtc: DateTime.utc(2026, 8, 2, 6, 30),
      newerUtc: DateTime.utc(2026, 8, 2, 7, 30),
      groupedDays: const ['2026-08-02', '2026-08-01'],
    ),
    _ => null,
  };

  if (proof == null) {
    test(
      'timezone proof requires an explicit supported TZ',
      () {},
      skip:
          'Set TZ to UTC, Asia/Shanghai, or America/Los_Angeles; '
          'the three-environment proof is a separate required gate.',
    );
    return;
  }

  test('maps a UTC instant to the configured literal local day', () {
    expect(localDayKey(DateTime.utc(2026, 8, 1, 16, 30)), proof.localDay);
  });

  test('groups records across the configured local midnight', () {
    final groups = groupRecordsByLocalDay([
      _record('older', proof.olderUtc),
      _record('newer', proof.newerUtc),
    ]);

    expect(groups.map((group) => group.key), proof.groupedDays);
    expect(groups.expand((group) => group.records).map((record) => record.id), [
      'newer',
      'older',
    ]);
  });

  if (timezone == 'America/Los_Angeles') {
    test('observes the real 2026 spring-forward transition boundary', () {
      final before = DateTime.utc(2026, 3, 8, 9, 59).toLocal();
      final after = DateTime.utc(2026, 3, 8, 10).toLocal();

      expect(
        (before.month, before.day, before.hour, before.minute),
        (3, 8, 1, 59),
      );
      expect(before.timeZoneOffset, const Duration(hours: -8));
      expect((after.month, after.day, after.hour, after.minute), (3, 8, 3, 0));
      expect(after.timeZoneOffset, const Duration(hours: -7));
      expect(localDayKey(DateTime.utc(2026, 3, 8, 9, 59)), '2026-03-08');
      expect(localDayKey(DateTime.utc(2026, 3, 8, 10)), '2026-03-08');

      final groups = groupRecordsByLocalDay([
        _record('before-midnight', DateTime.utc(2026, 3, 8, 7, 30)),
        _record('after-transition', DateTime.utc(2026, 3, 8, 10, 30)),
      ]);
      expect(groups.map((group) => group.key), ['2026-03-08', '2026-03-07']);
    });
  }
}

class _TimezoneProof {
  const _TimezoneProof({
    required this.localDay,
    required this.olderUtc,
    required this.newerUtc,
    required this.groupedDays,
  });

  final String localDay;
  final DateTime olderUtc;
  final DateTime newerUtc;
  final List<String> groupedDays;
}

TimelineRecord _record(String id, DateTime occurredAt) => TimelineRecord(
  id: id,
  type: RecordType.moment,
  occurredAt: occurredAt,
  attachments: const <Attachment>[],
  createdAt: occurredAt,
  updatedAt: occurredAt,
);
