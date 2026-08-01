import 'package:flutter/material.dart';

import '../../../../domain/models/timeline_record.dart';
import '../../../../domain/models/attachment.dart';
import '../../../media/domain/media_service.dart';
import '../../../media/presentation/media_picker.dart';

class MilestoneFields extends StatelessWidget {
  const MilestoneFields({
    super.key,
    required this.titleController,
    required this.currentDetails,
    required this.onChanged,
    required this.enabled,
    required this.onPicked,
    this.mediaPickerAdapter,
  });

  final TextEditingController titleController;
  final MilestoneDetails? Function() currentDetails;
  final ValueChanged<MilestoneDetails> onChanged;
  final bool enabled;
  final ValueChanged<PickedMedia> onPicked;
  final MediaPickerAdapter? mediaPickerAdapter;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        key: const Key('milestone-title'),
        controller: titleController,
        enabled: enabled,
        decoration: const InputDecoration(labelText: '里程碑标题'),
        onChanged: (value) => onChanged(
          MilestoneDetails(
            title: value,
            presetKey: currentDetails()?.presetKey,
          ),
        ),
      ),
      const SizedBox(height: 8),
      MediaPicker(
        allowedTypes: const <MediaType>{MediaType.image},
        adapter: mediaPickerAdapter,
        enabled: enabled,
        onPicked: onPicked,
      ),
    ],
  );
}
