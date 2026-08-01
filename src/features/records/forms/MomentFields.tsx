import { StyleSheet, Text, View } from 'react-native';

import type { RecordDraftAttachment } from '../../../domain/types';
import { colors, spacing } from '../../../ui/theme';
import { MediaPicker } from '../../media/MediaPicker';
import { MediaPreview } from '../../media/MediaPreview';

export function MomentFields({
  attachments,
  onAdd,
  onRemove,
}: {
  attachments: RecordDraftAttachment[];
  onAdd(attachment: Extract<RecordDraftAttachment, { kind: 'picked' }>): void;
  onRemove(index: number): void;
}) {
  return (
    <View style={styles.container}>
      <Text style={styles.hint}>写下这一刻，或稍后添加媒体。</Text>
      <MediaPicker allowedMedia={['image', 'video']} onPick={onAdd} />
      <View style={styles.previews}>
        {attachments.map((attachment, index) => (
          <MediaPreview
            key={`${attachment.kind}:${attachment.kind === 'picked' ? attachment.sourceUri : attachment.id}:${index}`}
            mediaType={attachment.mediaType}
            onRemove={() => onRemove(index)}
            uri={attachment.kind === 'picked'
              ? attachment.sourceUri
              : attachment.thumbnailPath ?? attachment.filePath}
          />
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { gap: spacing.xs },
  hint: { color: colors.muted, fontSize: 14 },
  previews: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
});
