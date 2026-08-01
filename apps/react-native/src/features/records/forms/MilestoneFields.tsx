import { useEffect, useRef, useState } from 'react';
import { StyleSheet, Text, TextInput, View } from 'react-native';

import type { MilestoneDetails, RecordDraftAttachment } from '../../../domain/types';
import { colors, radius, spacing } from '../../../ui/theme';
import { MediaPicker } from '../../media/MediaPicker';
import { MediaPreview } from '../../media/MediaPreview';

export function MilestoneFields({
  initialValue,
  attachments,
  resetKey,
  onChange,
  onAdd,
  onRemove,
}: {
  initialValue: MilestoneDetails;
  attachments: RecordDraftAttachment[];
  resetKey: string;
  onChange(details: MilestoneDetails): void;
  onAdd(attachment: Extract<RecordDraftAttachment, { kind: 'picked' }>): void;
  onRemove(index: number): void;
}) {
  const [value, setValue] = useState(() => toFormValue(initialValue));
  const valueRef = useRef(value);
  const previousResetKey = useRef(resetKey);

  useEffect(() => {
    if (previousResetKey.current === resetKey) {
      return;
    }
    previousResetKey.current = resetKey;
    const nextValue = toFormValue(initialValue);
    valueRef.current = nextValue;
    setValue(nextValue);
  }, [initialValue, resetKey]);

  const update = (nextValue: FormValue) => {
    valueRef.current = nextValue;
    setValue(nextValue);
    onChange({
      title: nextValue.title,
      presetKey: nextValue.presetKey.trim() === '' ? null : nextValue.presetKey,
    });
  };

  return (
    <View style={styles.container}>
      <View>
        <Text style={styles.label}>里程碑标题</Text>
        <TextInput
          accessibilityLabel="里程碑标题"
          onChangeText={(title) => update({ ...valueRef.current, title })}
          placeholder="例如：会翻身"
          style={styles.input}
          value={value.title}
        />
      </View>
      <View>
        <Text style={styles.label}>预设标识（可选）</Text>
        <TextInput
          accessibilityLabel="预设标识（可选）"
          autoCapitalize="none"
          onChangeText={(presetKey) => update({ ...valueRef.current, presetKey })}
          placeholder="例如：roll-over"
          style={styles.input}
          value={value.presetKey}
        />
      </View>
      <MediaPicker allowedMedia={['image']} onPick={onAdd} />
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

type FormValue = { title: string; presetKey: string };

function toFormValue(details: MilestoneDetails): FormValue {
  return { title: details.title, presetKey: details.presetKey ?? '' };
}

const styles = StyleSheet.create({
  container: { gap: spacing.md },
  label: { color: colors.text, fontSize: 15, fontWeight: '600', marginBottom: spacing.sm },
  input: {
    backgroundColor: colors.card,
    borderColor: colors.border,
    borderRadius: radius.md,
    borderWidth: 1,
    color: colors.text,
    fontSize: 16,
    paddingHorizontal: spacing.md,
    paddingVertical: 12,
  },
  previews: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
});
