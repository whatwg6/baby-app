import 'package:flutter/material.dart';

import '../../../../domain/models/attachment.dart';
import '../../../media/domain/media_service.dart';
import '../../../media/presentation/media_picker.dart';

class MomentFields extends StatelessWidget {
  const MomentFields({
    super.key,
    required this.enabled,
    required this.onPicked,
    this.mediaPickerAdapter,
  });

  final bool enabled;
  final ValueChanged<PickedMedia> onPicked;
  final MediaPickerAdapter? mediaPickerAdapter;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('记录这一刻的感受。'),
        const SizedBox(height: 8),
        MediaPicker(
          allowedTypes: const <MediaType>{MediaType.image, MediaType.video},
          adapter: mediaPickerAdapter,
          enabled: enabled,
          onPicked: onPicked,
        ),
      ],
    ),
  );
}
