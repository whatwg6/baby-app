import { useCallback, useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import type { RecordRepository } from '../../data/repositories';
import type { ActivityDetails, GrowthDetails, MilestoneDetails, TimelineRecord } from '../../domain/types';
import { colors, radius, spacing } from '../../ui/theme';
import { MediaPreview } from '../media/MediaPreview';
import { recordTypeLabel } from '../timeline/TimelineCard';

const loadErrorMessage = '无法读取记录，请重试';

export function RecordDetail({
  repository,
  recordId,
  onEdit,
  onDelete,
}: {
  repository: RecordRepository;
  recordId: string;
  onEdit?(target: string): void;
  onDelete?(): void;
}) {
  const [record, setRecord] = useState<TimelineRecord | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const reload = useCallback(async () => {
    if (recordId.trim().length === 0) {
      setRecord(null);
      setError(null);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      setRecord(await repository.get(recordId));
    } catch {
      setError(loadErrorMessage);
    } finally {
      setLoading(false);
    }
  }, [recordId, repository]);

  useEffect(() => {
    void reload();
  }, [reload]);

  if (loading && record === null) {
    return <Text style={styles.status}>正在读取记录…</Text>;
  }

  if (error !== null && record === null) {
    return <RetryState onRetry={reload} />;
  }

  if (record === null) {
    return <Text style={styles.status}>记录不存在</Text>;
  }

  return (
    <View style={styles.container}>
      {error === null ? null : <RetryState onRetry={reload} />}
      <Text style={styles.type}>{recordTypeLabel(record.type)}</Text>
      <Text style={styles.date}>{formatOccurredAt(record.occurredAt)}</Text>
      <RecordDetails record={record} />
      {record.note?.trim() ? <Text style={styles.note}>{record.note}</Text> : null}
      <View style={styles.attachments}>
        {record.attachments.map((attachment) => (
          <MediaPreview
            accessibilityLabel="记录媒体"
            key={attachment.id}
            mediaType={attachment.mediaType}
            uri={attachment.thumbnailPath ?? attachment.filePath}
          />
        ))}
      </View>
      <View style={styles.actions}>
        <Pressable
          accessibilityRole="button"
          onPress={() => onEdit?.(`/record/edit/${record.id}`)}
          style={styles.editAction}
        >
          <Text style={styles.editActionText}>编辑</Text>
        </Pressable>
        <Pressable
          accessibilityRole="button"
          accessibilityState={{ disabled: onDelete === undefined }}
          disabled={onDelete === undefined}
          onPress={() => onDelete?.()}
          style={[styles.deleteAction, onDelete === undefined ? styles.disabledAction : null]}
        >
          <Text style={styles.deleteActionText}>删除</Text>
        </Pressable>
      </View>
    </View>
  );
}

function RetryState({ onRetry }: { onRetry(): Promise<void> }) {
  return (
    <View style={styles.errorState}>
      <Text style={styles.error}>{loadErrorMessage}</Text>
      <Pressable accessibilityRole="button" onPress={() => void onRetry()}>
        <Text style={styles.retry}>重试</Text>
      </Pressable>
    </View>
  );
}

function RecordDetails({ record }: { record: TimelineRecord }) {
  switch (record.type) {
    case 'moment':
      return <Text style={styles.heading}>{record.note?.trim() || '珍贵时刻'}</Text>;
    case 'growth': {
      const details = record.details as GrowthDetails;
      return (
        <View style={styles.details}>
          {details.heightCm === null ? null : <Text style={styles.heading}>身高 {details.heightCm} cm</Text>}
          {details.weightKg === null ? null : <Text style={styles.heading}>体重 {details.weightKg} kg</Text>}
          {details.headCm === null ? null : <Text style={styles.heading}>头围 {details.headCm} cm</Text>}
        </View>
      );
    }
    case 'activity': {
      const details = record.details as ActivityDetails;
      return (
        <View style={styles.details}>
          <Text style={styles.heading}>{activityLabel(details.activityType)}</Text>
          {details.amount === null ? null : <Text style={styles.heading}>数量 {details.amount}</Text>}
          {details.durationMinutes === null ? null : <Text style={styles.heading}>时长 {details.durationMinutes} 分钟</Text>}
        </View>
      );
    }
    case 'milestone':
      return <Text style={styles.heading}>{(record.details as MilestoneDetails).title}</Text>;
  }
}

function activityLabel(type: ActivityDetails['activityType']): string {
  switch (type) {
    case 'feeding':
      return '喂养';
    case 'sleep':
      return '睡眠';
    case 'diaper':
      return '尿布';
  }
}

function formatOccurredAt(occurredAt: string): string {
  return new Date(occurredAt).toLocaleString('zh-CN', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

const styles = StyleSheet.create({
  container: { backgroundColor: colors.background, flex: 1, gap: spacing.md, padding: spacing.lg },
  status: { color: colors.muted, fontSize: 16, padding: spacing.lg },
  errorState: { gap: spacing.xs },
  error: { color: colors.danger, fontSize: 16 },
  retry: { color: colors.accent, fontSize: 16, fontWeight: '700' },
  type: { color: colors.muted, fontSize: 15, fontWeight: '600' },
  date: { color: colors.muted, fontSize: 14 },
  heading: { color: colors.text, fontSize: 18, fontWeight: '700' },
  details: { gap: spacing.sm },
  note: { color: colors.text, fontSize: 16, lineHeight: 24 },
  attachments: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  actions: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.md },
  editAction: { backgroundColor: colors.accent, borderRadius: radius.md, padding: spacing.md },
  editActionText: { color: colors.card, fontSize: 16, fontWeight: '700' },
  deleteAction: { borderColor: colors.danger, borderRadius: radius.md, borderWidth: 1, padding: spacing.md },
  disabledAction: { opacity: 0.45 },
  deleteActionText: { color: colors.danger, fontSize: 16, fontWeight: '700' },
});

export default RecordDetail;
