import { Pressable, StyleSheet, Text, View } from 'react-native';

import type { RecordType } from '../../domain/types';
import { colors, radius, spacing } from '../../ui/theme';

const filterOptions: { type: RecordType; label: string }[] = [
  { type: 'moment', label: '珍贵时刻' },
  { type: 'growth', label: '成长数据' },
  { type: 'activity', label: '活动' },
  { type: 'milestone', label: '里程碑' },
];

export function TimelineFilters({
  selectedTypes,
  onChange,
}: {
  selectedTypes: RecordType[];
  onChange(types: RecordType[]): void;
}) {
  return (
    <View accessibilityLabel="记录类型筛选" style={styles.container}>
      {filterOptions.map(({ type, label }) => {
        const selected = selectedTypes.includes(type);
        return (
          <Pressable
            key={type}
            accessibilityRole="button"
            accessibilityState={{ selected }}
            onPress={() => {
              onChange(
                selected
                  ? selectedTypes.filter((selectedType) => selectedType !== type)
                  : [...selectedTypes, type],
              );
            }}
            style={[styles.filter, selected ? styles.selectedFilter : null]}
          >
            <Text style={[styles.label, selected ? styles.selectedLabel : null]}>{label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  filter: {
    borderColor: colors.muted,
    borderRadius: radius.lg,
    borderWidth: 1,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.xs,
  },
  selectedFilter: { backgroundColor: colors.accent, borderColor: colors.accent },
  label: { color: colors.muted, fontSize: 14, fontWeight: '600' },
  selectedLabel: { color: colors.card },
});

export default TimelineFilters;
