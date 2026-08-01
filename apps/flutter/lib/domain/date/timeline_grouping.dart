import '../models/timeline_record.dart';

/// A local-calendar day and the records which occurred on that day.
class TimelineDayGroup {
  TimelineDayGroup({required this.key, required List<TimelineRecord> records})
    : records = List.unmodifiable(records);

  final String key;
  final List<TimelineRecord> records;
}

/// Builds a YYYY-MM-DD key from the device's local representation of an UTC instant.
String localDayKey(DateTime utc) {
  final local = utc.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// Sorts by newest UTC instant first, then groups records by local calendar day.
List<TimelineDayGroup> groupRecordsByLocalDay(List<TimelineRecord> records) {
  final sorted = List<TimelineRecord>.of(records)
    ..sort(
      (left, right) =>
          right.occurredAt.toUtc().compareTo(left.occurredAt.toUtc()),
    );

  final groups = <String, List<TimelineRecord>>{};
  for (final record in sorted) {
    groups.putIfAbsent(localDayKey(record.occurredAt), () => []).add(record);
  }

  return [
    for (final entry in groups.entries)
      TimelineDayGroup(key: entry.key, records: entry.value),
  ];
}
