import 'package:flutter/material.dart';

import 'record_type_picker.dart';

class AddRecordPage extends StatelessWidget {
  const AddRecordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(child: RecordTypePicker());
  }
}
