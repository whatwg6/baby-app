import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/timeline_record.dart';

class RecordTypePicker extends StatelessWidget {
  const RecordTypePicker({super.key, this.onSelected});

  final ValueChanged<RecordType>? onSelected;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('添加成长记录', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      for (final option in _options)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FilledButton.tonalIcon(
            onPressed: () {
              final callback = onSelected;
              if (callback != null) {
                callback(option.type);
              } else {
                context.go('/add/${option.type.name}');
              }
            },
            icon: Icon(option.icon),
            label: Text(option.label),
          ),
        ),
    ],
  );
}

const _options = [
  _RecordTypeOption(RecordType.moment, '珍贵时刻', Icons.auto_awesome_outlined),
  _RecordTypeOption(RecordType.growth, '成长数据', Icons.straighten_outlined),
  _RecordTypeOption(RecordType.activity, '日常活动', Icons.favorite_outline),
  _RecordTypeOption(RecordType.milestone, '里程碑', Icons.flag_outlined),
];

class _RecordTypeOption {
  const _RecordTypeOption(this.type, this.label, this.icon);

  final RecordType type;
  final String label;
  final IconData icon;
}
