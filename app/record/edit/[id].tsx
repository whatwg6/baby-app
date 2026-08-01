import { useCallback, useEffect, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useLocalSearchParams, useRouter, type Href } from 'expo-router';

import type { RecordRepository } from '../../../src/data/repositories';
import type { RecordDraft, TimelineRecord } from '../../../src/domain/types';
import { RecordEditor, toNewRecordInput } from '../../../src/features/records/RecordEditor';
import { useRecordRepository } from '../../../src/features/records/RecordRepositoryProvider';
import { colors, spacing } from '../../../src/ui/theme';

const loadErrorMessage = '无法读取记录，请重试';

type RecordLoadState = {
  requestedId: string;
  repository: RecordRepository;
  record: TimelineRecord | null;
  loading: boolean;
  error: string | null;
};

export default function EditRecordRoute() {
  const repository = useRecordRepository();
  const router = useRouter();
  const { id } = useLocalSearchParams<{ id?: string | string[] }>();
  const recordId = typeof id === 'string' ? id : '';
  const latestRequest = useRef(0);
  const [loadState, setLoadState] = useState<RecordLoadState>(() => ({
    requestedId: recordId,
    repository,
    record: null,
    loading: true,
    error: null,
  }));

  const reload = useCallback(async () => {
    const request = latestRequest.current + 1;
    latestRequest.current = request;
    if (recordId.trim() === '') {
      setLoadState({ requestedId: recordId, repository, record: null, loading: false, error: null });
      return;
    }

    setLoadState({ requestedId: recordId, repository, record: null, loading: true, error: null });
    try {
      const record = await repository.get(recordId);
      if (latestRequest.current === request) {
        setLoadState({ requestedId: recordId, repository, record, loading: false, error: null });
      }
    } catch {
      if (latestRequest.current === request) {
        setLoadState({
          requestedId: recordId,
          repository,
          record: null,
          loading: false,
          error: loadErrorMessage,
        });
      }
    }
  }, [recordId, repository]);

  useEffect(() => {
    void reload();
  }, [reload]);

  const currentLoadState = loadState.requestedId === recordId && loadState.repository === repository
    ? loadState
    : { requestedId: recordId, repository, record: null, loading: true, error: null };

  if (currentLoadState.loading) {
    return <Text style={styles.status}>正在读取记录…</Text>;
  }

  if (currentLoadState.error !== null) {
    return <RetryState onRetry={reload} />;
  }

  if (currentLoadState.record === null) {
    return <Text style={styles.status}>记录不存在</Text>;
  }

  const record = currentLoadState.record;

  return (
    <RecordEditor
      initialValue={toRecordDraft(record)}
      onSubmit={async (draft) => {
        await repository.update(recordId, toNewRecordInput(draft));
        router.replace(`/record/${recordId}` as Href);
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
