import 'package:flutter/material.dart';

import '../../../domain/date/age_label.dart';
import '../../../domain/models/attachment.dart';
import '../../../domain/models/baby.dart';
import '../../media/presentation/media_preview.dart';

class BabyHeader extends StatelessWidget {
  const BabyHeader({super.key, required this.baby, this.now});

  final Baby baby;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final birthDate = DateTime.parse(baby.birthDate);
    final age = calculateAgeLabel(birthDate, (now ?? DateTime.now)());

    return Row(
      children: [
        if (baby.avatarPath case final avatarPath?)
          MediaPreview(
            filePath: avatarPath,
            mediaType: MediaType.image,
            width: 48,
            height: 48,
            borderRadius: BorderRadius.circular(24),
            unavailableBuilder: (_) =>
                const CircleAvatar(child: Icon(Icons.child_care)),
          )
        else
          const CircleAvatar(child: Icon(Icons.child_care)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(baby.name, style: Theme.of(context).textTheme.titleLarge),
            Text(age, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ],
    );
  }
}
