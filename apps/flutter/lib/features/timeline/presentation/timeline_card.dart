import 'package:flutter/material.dart';

import '../../../domain/models/timeline_record.dart';

class TimelineCard extends StatelessWidget {
  const TimelineCard({super.key, required this.record, required this.onTap});

  final TimelineRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isMoment = record.type == RecordType.moment;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: isMoment
              ? _MomentCard(record: record)
              : _CompactCard(record: record),
        ),
      ),
    );
  }
}

class _MomentCard extends StatelessWidget {
  const _MomentCard({required this.record});

  final TimelineRecord record;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFFF8E4D9)),
        child: SizedBox(
          height: 132,
          width: double.infinity,
          child: Icon(Icons.photo_camera_outlined, size: 40),
        ),
      ),
      const SizedBox(height: 12),
      _RecordHeading(
        record: record,
        title: record.note?.trim().isNotEmpty == true ? record.note! : '珍贵时刻',
      ),
    ],
  );
}

class _CompactCard extends StatelessWidget {
  const _CompactCard({required this.record});

  final TimelineRecord record;

  @override
  Widget build(BuildContext context) =>
      _RecordHeading(record: record, title: recordSummary(record));
}

class _RecordHeading extends StatelessWidget {
  const _RecordHeading({required this.record, required this.title});

  final TimelineRecord record;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(_iconFor(record.type), color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 12),
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      Text(
        _timeLabel(record.occurredAt),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

String recordSummary(TimelineRecord record) {
  switch (record.details) {
    case GrowthDetails(:final heightCm, :final weightKg, :final headCm):
      final values = <String>[
        if (heightCm != null) '${_number(heightCm)} cm',
        if (weightKg != null) '${_number(weightKg)} kg',
        if (headCm != null) '${_number(headCm)} cm',
      ];
      return values.isEmpty ? '成长记录' : values.join(' · ');
    case ActivityDetails(
      :final activityType,
      :final amount,
      :final durationMinutes,
    ):
      final summary = durationMinutes != null
          ? '$durationMinutes 分钟'
          : amount != null
          ? '数量 ${_number(amount)}'
          : null;
      return '${_activityLabel(activityType)}${summary == null ? '' : ' · $summary'}';
    case MilestoneDetails(:final title):
      return title;
    case null:
      return record.note?.trim().isNotEmpty == true
          ? record.note!
          : _typeLabel(record.type);
  }
}

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

String _timeLabel(DateTime instant) {
  final local = instant.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _activityLabel(ActivityType activity) => switch (activity) {
  ActivityType.feeding => '喂养',
  ActivityType.sleep => '睡眠',
  ActivityType.diaper => '尿布',
};

String _typeLabel(RecordType type) => switch (type) {
  RecordType.moment => '珍贵时刻',
  RecordType.growth => '成长记录',
  RecordType.activity => '日常活动',
  RecordType.milestone => '成长里程碑',
};

IconData _iconFor(RecordType type) => switch (type) {
  RecordType.moment => Icons.auto_awesome,
  RecordType.growth => Icons.straighten,
  RecordType.activity => Icons.nightlight_round,
  RecordType.milestone => Icons.flag_outlined,
};
