import { Pressable, StyleSheet, Text, View } from 'react-native';

import type { ActivityDetails, GrowthDetails, MilestoneDetails, TimelineRecord } from '../../domain/types';
import { colors, radius, spacing } from '../../ui/theme';
import { MediaPreview } from '../media/MediaPreview';

const activityLabels: Record<ActivityDetails['activityType'], string> = {
  feeding: '喂养',
  sleep: '睡眠',
  diaper: '尿布',
};

export function getTimelineSummary(record: TimelineRecord): string {
  switch (record.type) {
    case 'moment':
      return record.note?.trim() || '珍贵时刻';
    case 'growth': {
      const details = record.details as GrowthDetails;
      const measurements = [
        details.heightCm === null ? null : `身高 ${details.heightCm} cm`,
        details.weightKg === null ? null : `体重 ${details.weightKg} kg`,
        details.headCm === null ? null : `头围 ${details.headCm} cm`,
      ].filter((measurement): measurement is string => measurement !== null);
      return measurements.join(' · ') || '成长数据';
    }
    case 'activity': {
      const details = record.details as ActivityDetails;
      const values = [
        activityLabels[details.activityType],
        details.amount === null ? null : `数量 ${details.amount}`,
        details.durationMinutes === null ? null : `${details.durationMinutes} 分钟`,
      ].filter((value): value is string => value !== null);
      return values.join(' · ');
    }
    case 'milestone':
      return (record.details as MilestoneDetails).title;
  }
}

export function TimelineCard({
  record,
  onPress,
}: {
  record: TimelineRecord;
  onPress?(): void;
}) {
  const firstAttachment = record.attachments[0];

  const content = (
    <>
      {record.type === 'moment' && firstAttachment !== undefined ? (
        <MediaPreview
          accessibilityLabel="珍贵时刻照片"
          mediaType={firstAttachment.mediaType}
          uri={firstAttachment.mediaType === 'video'
            ? firstAttachment.filePath
            : firstAttachment.thumbnailPath ?? firstAttachment.filePath}
        />
      ) : null}
      <View style={styles.content}>
        <Text style={styles.type}>{recordTypeLabel(record.type)}</Text>
        <Text style={styles.summary}>{getTimelineSummary(record)}</Text>
        {record.type !== 'moment' && record.note?.trim() ? (
          <Text style={styles.note}>{record.note}</Text>
        ) : null}
      </View>
    </>
  );

  if (onPress !== undefined) {
    return (
      <Pressable
        accessibilityLabel={`时间轴记录 ${record.id}`}
        accessibilityRole="button"
        onPress={onPress}
        style={styles.card}
      >
        {content}
      </Pressable>
    );
  }

  return (
    <View accessibilityLabel={`时间轴记录 ${record.id}`} style={styles.card}>
      {content}
    </View>
  );
}

export function recordTypeLabel(type: TimelineRecord['type']): string {
  switch (type) {
    case 'moment':
      return '珍贵时刻';
    case 'growth':
      return '成长数据';
    case 'activity':
      return '活动记录';
    case 'milestone':
      return '里程碑';
  }
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: colors.card,
    borderRadius: radius.md,
    flexDirection: 'row',
    gap: spacing.md,
    padding: spacing.md,
  },
  content: { flex: 1, gap: spacing.xs },
  type: { color: colors.muted, fontSize: 13, fontWeight: '600' },
  summary: { color: colors.text, fontSize: 16, fontWeight: '700' },
  note: { color: colors.muted, fontSize: 14 },
});

export default TimelineCard;
