import 'package:flutter/material.dart';

import '../../../domain/date/timeline_grouping.dart';
import 'timeline_card.dart';

class TimelineSection extends StatelessWidget {
  const TimelineSection({
    super.key,
    required this.group,
    required this.label,
    required this.onRecordTap,
  });

  final TimelineDayGroup group;
  final String label;
  final ValueChanged<String> onRecordTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(label, style: Theme.of(context).textTheme.titleLarge),
      ),
      for (final record in group.records)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TimelineCard(
            record: record,
            onTap: () => onRecordTap(record.id),
          ),
        ),
    ],
  );
}
