import 'package:flutter/material.dart';

import '../../../../domain/models/timeline_record.dart';

class GrowthFields extends StatelessWidget {
  const GrowthFields({
    super.key,
    required this.heightController,
    required this.weightController,
    required this.headController,
    required this.currentDetails,
    required this.onChanged,
    required this.enabled,
  });

  final TextEditingController heightController;
  final TextEditingController weightController;
  final TextEditingController headController;
  final GrowthDetails? Function() currentDetails;
  final ValueChanged<GrowthDetails> onChanged;
  final bool enabled;

  void _changed(String field, String value) {
    final current = currentDetails();
    final parsed = _decimalValue(value);
    onChanged(
      GrowthDetails(
        heightCm: field == 'height' ? parsed : current?.heightCm,
        weightKg: field == 'weight' ? parsed : current?.weightKg,
        headCm: field == 'head' ? parsed : current?.headCm,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextFormField(
        key: const Key('growth-height'),
        controller: heightController,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: '身高（cm）'),
        onChanged: (value) => _changed('height', value),
      ),
      TextFormField(
        key: const Key('growth-weight'),
        controller: weightController,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: '体重（kg）'),
        onChanged: (value) => _changed('weight', value),
      ),
      TextFormField(
        key: const Key('growth-head'),
        controller: headController,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: '头围（cm）'),
        onChanged: (value) => _changed('head', value),
      ),
    ],
  );
}

double? _decimalValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed) ?? double.nan;
}
