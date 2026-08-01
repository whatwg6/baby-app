import { useCallback, useMemo } from 'react';
import {
  Pressable,
  SectionList,
  StyleSheet,
  Text,
  View,
} from 'react-native';

import type { RecordRepository } from '../../data/repositories';
import { groupRecordsByDay } from '../../domain/date';
import type { Baby, RecordType, TimelineRecord } from '../../domain/types';
import { colors, radius, spacing } from '../../ui/theme';
import BabyHeader from '../baby/BabyHeader';
import TimelineCard from './TimelineCard';
import TimelineFilters from './TimelineFilters';
import { useTimeline } from './useTimeline';

type TimelineSection = {
  key: string;
  data: TimelineRecord[];
};

export function TimelineScreen({
  repository,
  baby,
  onAddPress,
  onRecordPress,
}: {
  repository: RecordRepository;
  baby: Baby;
  onAddPress?(): void;
  onRecordPress?(record: TimelineRecord): void;
}) {
  const {
    records,
    selectedTypes,
    loading,
    loadingMore,
    error,
    loadMoreError,
    loadMore,
    retry,
    setSelectedTypes,
  } = useTimeline(repository);
  const sections = useMemo<TimelineSection[]>(() => (
    groupRecordsByDay(records).map((group) => ({
      key: group.key,
      data: group.records,
    }))
  ), [records]);
  const noRecords = !loading && error === null && records.length === 0;

  const renderItem = useCallback(({ item }: { item: TimelineRecord }) => (
    <View style={styles.card}>
      <TimelineCard
        record={item}
        onPress={onRecordPress === undefined ? undefined : () => onRecordPress(item)}
      />
    </View>
  ), [onRecordPress]);

  const renderSectionHeader = useCallback(({ section }: { section: TimelineSection }) => (
    <Text accessibilityLabel="时间轴日期" style={styles.dayHeading}>
      {formatDayHeading(section.key)}
    </Text>
  ), []);

  const handleEndReached = useCallback(() => {
    void loadMore().catch(() => undefined);
  }, [loadMore]);

  return (
    <SectionList<TimelineRecord, TimelineSection>
      contentContainerStyle={styles.container}
      keyExtractor={recordKeyExtractor}
      ListFooterComponent={(
        <TimelineListFooter
          error={loadMoreError}
          loading={loadingMore}
          onRetry={retry}
        />
      )}
      ListHeaderComponent={(
        <TimelineListHeader
          baby={baby}
          error={error}
          loading={loading}
          noRecords={noRecords}
          onAddPress={onAddPress}
          onRetry={retry}
          onSelectedTypesChange={setSelectedTypes}
          recordsLoaded={records.length > 0}
          selectedTypes={selectedTypes}
        />
      )}
      onEndReached={handleEndReached}
      onEndReachedThreshold={0.4}
      renderItem={renderItem}
      renderSectionHeader={renderSectionHeader}
      sections={sections}
      stickySectionHeadersEnabled={false}
      testID="timeline-section-list"
    />
  );
}

function TimelineListFooter({
  error,
  loading,
  onRetry,
}: {
  error: string | null;
  loading: boolean;
  onRetry(): Promise<void>;
}) {
  if (loading) {
    return <Text style={styles.status}>正在读取更多记录…</Text>;
  }
  if (error === null) {
    return null;
  }
  return (
    <View style={styles.errorState} testID="timeline-load-more-error">
      <Text style={styles.error}>{error}</Text>
      <Pressable
        accessibilityRole="button"
        onPress={() => void onRetry().catch(() => undefined)}
      >
        <Text style={styles.retry}>重试</Text>
      </Pressable>
    </View>
  );
}

function TimelineListHeader({
  baby,
  error,
  loading,
  noRecords,
  onAddPress,
  onRetry,
  onSelectedTypesChange,
  recordsLoaded,
  selectedTypes,
}: {
  baby: Baby;
  error: string | null;
  loading: boolean;
  noRecords: boolean;
  onAddPress?(): void;
  onRetry(): Promise<void>;
  onSelectedTypesChange(types: RecordType[]): void;
  recordsLoaded: boolean;
  selectedTypes: RecordType[];
}) {
  return (
    <View style={styles.header}>
      <BabyHeader baby={baby} />
      <Text style={styles.title}>成长时间轴</Text>
      <TimelineFilters selectedTypes={selectedTypes} onChange={onSelectedTypesChange} />

      {error === null ? null : (
        <View style={styles.errorState}>
          <Text style={styles.error}>{error}</Text>
          <Pressable
            accessibilityRole="button"
            onPress={() => void onRetry().catch(() => undefined)}
          >
            <Text style={styles.retry}>重试</Text>
          </Pressable>
        </View>
      )}
      {loading && !recordsLoaded ? <Text style={styles.status}>正在读取记录…</Text> : null}
      {noRecords ? (
        <View style={styles.emptyState}>
          <Text style={styles.emptyTitle}>
            {selectedTypes.length === 0 ? '还没有成长记录' : '暂无相关记录'}
          </Text>
          {selectedTypes.length === 0 ? (
            <Pressable
              accessibilityRole="button"
              onPress={onAddPress}
              style={styles.action}
            >
              <Text style={styles.actionText}>记录第一个瞬间</Text>
            </Pressable>
          ) : null}
        </View>
      ) : null}
    </View>
  );
}

function recordKeyExtractor(record: TimelineRecord): string {
  return record.id;
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
  container: {
    backgroundColor: colors.background,
    flexGrow: 1,
    padding: spacing.lg,
  },
  header: { gap: spacing.lg, marginBottom: spacing.lg },
  title: { color: colors.text, fontSize: 22, fontWeight: '700' },
  status: { color: colors.muted, fontSize: 16, paddingVertical: spacing.sm },
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
  dayHeading: {
    backgroundColor: colors.background,
    color: colors.text,
    fontSize: 17,
    fontWeight: '700',
    paddingBottom: spacing.sm,
    paddingTop: spacing.sm,
  },
  card: { paddingBottom: spacing.sm },
});

export default TimelineScreen;
