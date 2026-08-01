import 'package:flutter/material.dart';

import '../../../domain/models/timeline_record.dart';

class TimelineFilters extends StatelessWidget {
  const TimelineFilters({
    super.key,
    required this.selectedTypes,
    required this.onToggle,
    required this.onClear,
  });

  final Set<RecordType> selectedTypes;
  final ValueChanged<RecordType> onToggle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    const labels = {
      RecordType.moment: '时刻',
      RecordType.growth: '成长',
      RecordType.activity: '活动',
      RecordType.milestone: '里程碑',
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final type in RecordType.values)
          FilterChip(
            label: Text(labels[type]!),
            selected: selectedTypes.contains(type),
            onSelected: (_) => onToggle(type),
          ),
        if (selectedTypes.isNotEmpty)
          TextButton(onPressed: onClear, child: const Text('清除筛选')),
      ],
    );
  }
}
