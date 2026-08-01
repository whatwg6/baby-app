import '../../../data/repositories/record_repository.dart';
import '../../../domain/models/attachment.dart';
import '../../../domain/models/record_draft.dart';
import '../../../domain/models/timeline_record.dart';
import '../domain/media_service.dart';

Future<TimelineRecord> saveRecordWithMedia({
  required RecordRepository repository,
  required MediaService mediaService,
  required RecordDraft draft,
  String? recordId,
  Iterable<Attachment> previousAttachments = const <Attachment>[],
}) async {
  final staged = <StagedMedia>[];
  try {
    for (final attachment in draft.attachments) {
      if (attachment case PickedAttachment(
        :final sourcePath,
        :final mediaType,
      )) {
        staged.add(
          await mediaService.stage(
            PickedMedia(sourcePath: sourcePath, mediaType: mediaType),
          ),
        );
      }
    }
  } catch (_) {
    await _rollbackAll(mediaService, staged);
    rethrow;
  }

  try {
    var pickedIndex = 0;
    final attachments = draft.attachments.map((attachment) {
      return switch (attachment) {
        ExistingAttachment(
          :final id,
          :final mediaType,
          :final filePath,
          :final thumbnailPath,
        ) =>
          NewAttachmentInput(
            id: id,
            mediaType: mediaType,
            filePath: filePath,
            thumbnailPath: thumbnailPath,
          ),
        PickedAttachment(:final mediaType) => () {
          final media = staged[pickedIndex++];
          return NewAttachmentInput(
            mediaType: mediaType,
            filePath: media.finalPath,
            thumbnailPath: media.thumbnailFinalPath,
          );
        }(),
      };
    }).toList();
    final input = NewRecordInput(
      type: draft.type,
      occurredAt: draft.occurredAt.toUtc(),
      note: draft.note,
      details: draft.details,
      attachments: attachments,
    );

    final saved = await repository.inTransaction((transaction) async {
      final value = recordId == null
          ? await transaction.create(input)
          : await transaction.update(recordId, input);
      for (final media in staged) {
        await mediaService.commit(media);
      }
      return value;
    });
    if (mediaService case final MediaLifecycleOwnership owner) {
      owner.releaseOwnership(staged);
    }

    final retainedIds = draft.attachments
        .whereType<ExistingAttachment>()
        .map((attachment) => attachment.id)
        .toSet();
    final oldPaths = previousAttachments
        .where((attachment) => !retainedIds.contains(attachment.id))
        .expand(
          (attachment) => <String?>[
            attachment.filePath,
            attachment.thumbnailPath,
          ],
        )
        .whereType<String>()
        .toList();
    if (oldPaths.isNotEmpty) {
      try {
        await mediaService.remove(oldPaths);
      } catch (_) {
        // The database commit is terminal; orphan cleanup can safely retry later.
      }
    }
    return saved;
  } catch (_) {
    await _rollbackAll(mediaService, staged);
    rethrow;
  }
}

Future<void> _rollbackAll(
  MediaService mediaService,
  Iterable<StagedMedia> staged,
) async {
  for (final media in staged) {
    try {
      await mediaService.rollback(media);
    } catch (_) {
      // Preserve the triggering error while attempting every compensation.
    }
  }
}
