import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import type { RecordRepository } from '../../data/repositories';
import { groupRecordsByDay } from '../../domain/date';
import type { Baby, TimelineRecord } from '../../domain/types';
import BabyHeader from '../baby/BabyHeader';
import { colors, radius, spacing } from '../../ui/theme';
import TimelineCard from './TimelineCard';
import TimelineFilters from './TimelineFilters';
import { useTimeline } from './useTimeline';

export function TimelineScreen({
  repository,
  baby,
  onRecordPress,
}: {
  repository: RecordRepository;
  baby: Baby;
  onRecordPress?(record: TimelineRecord): void;
}) {
  const { records, selectedTypes, loading, error, reload, setSelectedTypes } = useTimeline(repository);
  const groups = groupRecordsByDay(records);
  const noRecords = !loading && error === null && records.length === 0;

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <BabyHeader baby={baby} />
      <Text style={styles.title}>成长时间轴</Text>
      <TimelineFilters selectedTypes={selectedTypes} onChange={setSelectedTypes} />

      {error === null ? null : (
        <View style={styles.errorState}>
          <Text style={styles.error}>{error}</Text>
          <Pressable accessibilityRole="button" onPress={() => void reload().catch(() => undefined)}>
            <Text style={styles.retry}>重试</Text>
          </Pressable>
        </View>
      )}
      {loading && records.length === 0 ? <Text style={styles.status}>正在读取记录…</Text> : null}
      {noRecords ? (
        <View style={styles.emptyState}>
          <Text style={styles.emptyTitle}>
            {selectedTypes.length === 0 ? '还没有成长记录' : '暂无相关记录'}
          </Text>
          {selectedTypes.length === 0 ? (
            <Pressable style={styles.action} accessibilityRole="button">
              <Text style={styles.actionText}>记录第一个瞬间</Text>
            </Pressable>
          ) : null}
        </View>
      ) : null}
      {groups.map((group) => (
        <View key={group.key} style={styles.dayGroup}>
          <Text accessibilityLabel="时间轴日期" style={styles.dayHeading}>
            {formatDayHeading(group.key)}
          </Text>
          <View style={styles.cards}>
            {group.records.map((record) => (
              <TimelineCard
                key={record.id}
                record={record}
                onPress={onRecordPress === undefined ? undefined : () => onRecordPress(record)}
              />
            ))}
          </View>
        </View>
      ))}
    </ScrollView>
  );
}

export function formatDayHeading(day: string, now = new Date()): string {
  const [year, month, date] = day.split('-').map(Number);
  const target = new Date(year, month - 1, date);
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);

  if (target.getTime() === today.getTime()) {
    return '今天';
  }
  if (target.getTime() === yesterday.getTime()) {
    return '昨天';
  }
  return target.toLocaleDateString('zh-CN', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
}

const styles = StyleSheet.create({
  container: { backgroundColor: colors.background, gap: spacing.lg, padding: spacing.lg },
  title: { color: colors.text, fontSize: 22, fontWeight: '700' },
  status: { color: colors.muted, fontSize: 16 },
  errorState: { gap: spacing.xs },
  error: { color: colors.danger, fontSize: 16 },
  retry: { color: colors.accent, fontSize: 16, fontWeight: '700' },
  emptyState: { alignItems: 'center', gap: spacing.md, paddingVertical: spacing.xl },
  emptyTitle: { color: colors.muted, fontSize: 18 },
  action: {
    backgroundColor: colors.accent,
    borderRadius: radius.md,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.md,
  },
  actionText: { color: colors.card, fontSize: 16, fontWeight: '600' },
  dayGroup: { gap: spacing.sm },
  dayHeading: { color: colors.text, fontSize: 17, fontWeight: '700' },
  cards: { gap: spacing.sm },
});

export default TimelineScreen;
