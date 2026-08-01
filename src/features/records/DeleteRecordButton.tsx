import { useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';

import type { RecordRepository } from '../../data/repositories';
import { colors, radius, spacing } from '../../ui/theme';
import type { MediaCleanupIssue, MediaService } from '../media/mediaService';

export const DELETE_CLEANUP_PENDING_MESSAGE = '记录已删除，媒体将在稍后清理';

export function DeleteRecordButton({
  repository,
  media,
  recordId,
  disabled = false,
  onDeleted,
  onCleanupPending,
}: {
  repository: RecordRepository;
  media: MediaService;
  recordId: string;
  disabled?: boolean;
  onDeleted?(): void;
  onCleanupPending?(issue: MediaCleanupIssue): void;
}) {
  const [deleting, setDeleting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const confirmDelete = () => {
    if (disabled || deleting) {
      return;
    }
    setMessage(null);
    Alert.alert(
      '删除这条记录？此操作无法撤销。',
      undefined,
      [
        { text: '取消', style: 'cancel' },
        {
          text: '删除',
          style: 'destructive',
          onPress: () => {
            void deleteRecord();
          },
        },
      ],
    );
  };

  const deleteRecord = async () => {
    if (deleting) {
      return;
    }
    setDeleting(true);
    setMessage(null);
    try {
      let attachments: Awaited<ReturnType<RecordRepository['delete']>>;
      try {
        attachments = await repository.delete(recordId);
      } catch {
        setMessage('删除失败（数据库阶段），请重试');
        return;
      }
      const paths = [...new Set(attachments.flatMap((attachment) => [
        attachment.filePath,
        ...(attachment.thumbnailPath === null ? [] : [attachment.thumbnailPath]),
      ]))];
      if (paths.length > 0) {
        try {
          await media.remove(paths);
        } catch (cause) {
          const issue: MediaCleanupIssue = { scope: 'record', paths, cause };
          setMessage(DELETE_CLEANUP_PENDING_MESSAGE);
          try {
            onCleanupPending?.(issue);
          } catch (notificationError) {
            setMessage(
              `${DELETE_CLEANUP_PENDING_MESSAGE}；无法登记清理提醒：${errorMessage(notificationError)}`,
            );
          }
        }
      }
      try {
        onDeleted?.();
      } catch (navigationError) {
        setMessage(`记录已删除，但页面刷新失败：${errorMessage(navigationError)}`);
      }
    } finally {
      setDeleting(false);
    }
  };

  const isDisabled = disabled || deleting;
  return (
    <View style={styles.container}>
      <Pressable
        accessibilityRole="button"
        accessibilityState={{ disabled: isDisabled }}
        disabled={isDisabled}
        onPress={confirmDelete}
        style={[styles.action, isDisabled ? styles.disabled : null]}
      >
        <Text style={styles.text}>{deleting ? '正在删除…' : '删除'}</Text>
      </Pressable>
      {message === null ? null : (
        <Text style={message === DELETE_CLEANUP_PENDING_MESSAGE ? styles.warning : styles.error}>
          {message}
        </Text>
      )}
    </View>
  );
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

const styles = StyleSheet.create({
  container: { gap: spacing.sm },
  action: {
    borderColor: colors.danger,
    borderRadius: radius.md,
    borderWidth: 1,
    padding: spacing.md,
  },
  disabled: { opacity: 0.45 },
  text: { color: colors.danger, fontSize: 16, fontWeight: '700' },
  warning: { color: colors.muted, fontSize: 14 },
  error: { color: colors.danger, fontSize: 14 },
});

export default DeleteRecordButton;
