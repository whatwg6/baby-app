import { Pressable, StyleSheet, Text, View } from 'react-native';

import type { RecordType } from '../../domain/types';
import { colors, radius, spacing } from '../../ui/theme';

const recordTypes: readonly [RecordType, string, string][] = [
  ['moment', '珍贵时刻', '记录值得珍藏的瞬间'],
  ['growth', '成长数据', '记录身高、体重或头围'],
  ['activity', '日常活动', '记录喂养、睡眠或尿布'],
  ['milestone', '里程碑', '记录成长中的新本领'],
];

export function RecordTypePicker({ onSelect }: { onSelect(type: RecordType): void }) {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>选择记录类型</Text>
      {recordTypes.map(([type, label, description]) => (
        <Pressable
          accessibilityRole="button"
          key={type}
          onPress={() => onSelect(type)}
          style={styles.option}
        >
          <Text style={styles.optionLabel}>{label}</Text>
          <Text style={styles.optionDescription}>{description}</Text>
        </Pressable>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { backgroundColor: colors.background, flex: 1, gap: spacing.md, padding: spacing.lg },
  title: { color: colors.text, fontSize: 20, fontWeight: '700', marginBottom: spacing.sm },
  option: {
    backgroundColor: colors.card,
    borderColor: colors.border,
    borderRadius: radius.md,
    borderWidth: 1,
    gap: spacing.xs,
    padding: spacing.md,
  },
  optionLabel: { color: colors.text, fontSize: 17, fontWeight: '700' },
  optionDescription: { color: colors.muted, fontSize: 14 },
});
