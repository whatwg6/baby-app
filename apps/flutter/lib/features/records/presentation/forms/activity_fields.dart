import 'package:flutter/material.dart';

import '../../../../domain/models/timeline_record.dart';

class ActivityFields extends StatelessWidget {
  const ActivityFields({
    super.key,
    required this.activityType,
    required this.currentType,
    required this.amountController,
    required this.durationController,
    required this.onChanged,
    required this.enabled,
  });

  final ActivityType? activityType;
  final ActivityType? Function() currentType;
  final TextEditingController amountController;
  final TextEditingController durationController;
  final ValueChanged<ActivityDetails> onChanged;
  final bool enabled;

  void _changed(ActivityType? type) {
    if (type == null) return;
    onChanged(
      ActivityDetails(
        activityType: type,
        amount: _decimalValue(amountController.text),
        durationMinutes: _integerValue(durationController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      DropdownButtonFormField<ActivityType>(
        key: const Key('activity-type'),
        initialValue: activityType,
        decoration: const InputDecoration(labelText: '活动类型'),
        items: const [
          DropdownMenuItem(value: ActivityType.feeding, child: Text('喂养')),
          DropdownMenuItem(value: ActivityType.sleep, child: Text('睡眠')),
          DropdownMenuItem(value: ActivityType.diaper, child: Text('尿布')),
        ],
        onChanged: enabled ? (value) => _changed(value) : null,
      ),
      TextFormField(
        key: const Key('activity-amount'),
        controller: amountController,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: '数量'),
        onChanged: (_) => _changed(currentType()),
      ),
      TextFormField(
        key: const Key('activity-duration'),
        controller: durationController,
        enabled: enabled,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: '时长（分钟）'),
        onChanged: (_) => _changed(currentType()),
      ),
    ],
  );
}

double? _decimalValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed) ?? double.nan;
}

int? _integerValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return int.tryParse(trimmed) ?? 0;
}
