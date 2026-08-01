import { useCallback, useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useLocalSearchParams, useRouter, type Href } from 'expo-router';

import type { RecordDraft, TimelineRecord } from '../../../src/domain/types';
import { RecordEditor, toNewRecordInput } from '../../../src/features/records/RecordEditor';
import { useRecordRepository } from '../../../src/features/records/RecordRepositoryProvider';
import { colors, spacing } from '../../../src/ui/theme';

const loadErrorMessage = '无法读取记录，请重试';

export default function EditRecordRoute() {
  const repository = useRecordRepository();
  const router = useRouter();
  const { id } = useLocalSearchParams<{ id?: string | string[] }>();
  const recordId = typeof id === 'string' ? id : '';
  const [record, setRecord] = useState<TimelineRecord | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const reload = useCallback(async () => {
    if (recordId.trim() === '') {
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
    <RecordEditor
      initialValue={toRecordDraft(record)}
      onSubmit={async (draft) => {
        await repository.update(record.id, toNewRecordInput(draft));
        router.replace(`/record/${record.id}` as Href);
      }}
      type={record.type}
    />
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

function toRecordDraft(record: TimelineRecord): RecordDraft {
  return {
    type: record.type,
    occurredAt: record.occurredAt,
    note: record.note,
    details: record.details,
    attachments: record.attachments.map((attachment) => ({
      kind: 'existing' as const,
      id: attachment.id,
      mediaType: attachment.mediaType,
      filePath: attachment.filePath,
      thumbnailPath: attachment.thumbnailPath,
    })),
  };
}

const styles = StyleSheet.create({
  status: { color: colors.muted, fontSize: 16, padding: spacing.lg },
  errorState: { backgroundColor: colors.background, flex: 1, gap: spacing.xs, padding: spacing.lg },
  error: { color: colors.danger, fontSize: 16 },
  retry: { color: colors.accent, fontSize: 16, fontWeight: '700' },
});
