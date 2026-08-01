import {
  createContext,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { Alert, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

import { colors, radius, spacing } from '../../ui/theme';
import { BackupServiceError, type BackupService } from './backupService';

type BackupContextValue = {
  service: BackupService;
  onDataChanged?(): void;
};

const BackupContext = createContext<BackupContextValue | null>(null);

export function BackupServiceProvider({
  service,
  onDataChanged,
  children,
}: {
  service: BackupService;
  onDataChanged?(): void;
  children: ReactNode;
}) {
  const value = useMemo(
    () => ({ service, onDataChanged }),
    [onDataChanged, service],
  );
  return <BackupContext.Provider value={value}>{children}</BackupContext.Provider>;
}

export function BackupActions({
  babyName,
  service: suppliedService,
  onDataChanged: suppliedOnDataChanged,
}: {
  babyName: string;
  service?: BackupService;
  onDataChanged?(): void;
}) {
  const context = useContext(BackupContext);
  const service = suppliedService ?? context?.service;
  const onDataChanged = suppliedOnDataChanged ?? context?.onDataChanged;
  const [busy, setBusy] = useState<'export' | 'restore' | 'clear' | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [isConfirmingClear, setIsConfirmingClear] = useState(false);
  const [confirmationName, setConfirmationName] = useState('');

  if (service === undefined) {
    return null;
  }

  const exportBackup = async () => {
    if (busy !== null) {
      return;
    }
    setBusy('export');
    setMessage(null);
    try {
      const result = await service.export();
      if (result.shared) {
        setMessage(result.cleanupWarning ?? '备份已导出');
      } else {
        setMessage(`备份已保留：${result.archivePath}`);
      }
    } catch (cause) {
      setMessage(displayError(cause));
    } finally {
      setBusy(null);
      onDataChanged?.();
    }
  };

  const startRestore = () => {
    if (busy !== null) {
      return;
    }
    Alert.alert(
      '恢复备份会替换当前数据。继续吗？',
      '恢复失败时会自动保留当前数据。',
      [
        { text: '取消', style: 'cancel' },
        {
          text: '继续恢复',
          style: 'destructive',
          onPress: () => {
            void restoreBackup();
          },
        },
      ],
    );
  };

  const restoreBackup = async () => {
    setBusy('restore');
    setMessage(null);
    try {
      const result = await service.restore();
      if (result.status === 'cancelled') {
        setMessage('已取消恢复');
      } else {
        setMessage(result.cleanupWarning ?? '备份已恢复');
      }
    } catch (cause) {
      setMessage(displayError(cause));
    } finally {
      setBusy(null);
      onDataChanged?.();
    }
  };

  const clearData = async () => {
    if (busy !== null || confirmationName !== babyName) {
      return;
    }
    setBusy('clear');
    setMessage(null);
    try {
      const result = await service.clear();
      setMessage(result.cleanupPending
        ? `数据已清空；${result.warning ?? '媒体将在稍后清理'}`
        : '全部数据已清空');
      setIsConfirmingClear(false);
      setConfirmationName('');
    } catch (cause) {
      setMessage(displayError(cause));
    } finally {
      setBusy(null);
      onDataChanged?.();
    }
  };

  const clearEnabled = busy === null && confirmationName === babyName;
  return (
    <View style={styles.container}>
      <Text style={styles.heading}>本地数据</Text>
      <View style={styles.actions}>
        <ActionButton
          disabled={busy !== null}
          label={busy === 'export' ? '正在导出…' : '导出备份'}
          onPress={() => void exportBackup()}
        />
        <ActionButton
          disabled={busy !== null}
          label={busy === 'restore' ? '正在恢复…' : '从备份恢复'}
          onPress={startRestore}
        />
        <ActionButton
          danger
          disabled={busy !== null}
          label="清空全部数据"
          onPress={() => {
            setMessage(null);
            setIsConfirmingClear(true);
            setConfirmationName('');
          }}
        />
      </View>
      {isConfirmingClear ? (
        <View style={styles.confirmation}>
          <Text style={styles.warning}>此操作无法撤销。清空后所有记录与媒体都将删除。</Text>
          <Text style={styles.help}>请输入宝宝姓名“{babyName}”确认。</Text>
          <TextInput
            accessibilityLabel="输入宝宝姓名确认"
            autoCapitalize="none"
            autoCorrect={false}
            onChangeText={setConfirmationName}
            style={styles.input}
            value={confirmationName}
          />
          <View style={styles.confirmationActions}>
            <ActionButton
              disabled={busy !== null}
              label="取消"
              onPress={() => {
                setIsConfirmingClear(false);
                setConfirmationName('');
              }}
            />
            <ActionButton
              danger
              disabled={!clearEnabled}
              label={busy === 'clear' ? '正在清空…' : '确认清空'}
              onPress={() => void clearData()}
            />
          </View>
        </View>
      ) : null}
      {message === null ? null : <Text style={styles.message}>{message}</Text>}
    </View>
  );
}

function ActionButton({
  label,
  disabled,
  danger = false,
  onPress,
}: {
  label: string;
  disabled: boolean;
  danger?: boolean;
  onPress(): void;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ disabled }}
      disabled={disabled}
      onPress={onPress}
      style={[
        styles.action,
        danger ? styles.dangerAction : styles.standardAction,
        disabled ? styles.disabled : null,
      ]}
    >
      <Text style={danger ? styles.dangerText : styles.actionText}>{label}</Text>
    </Pressable>
  );
}

function displayError(cause: unknown): string {
  if (cause instanceof AggregateError) {
    return `操作失败，且回滚或清理未完全成功：${cause.errors.map(errorMessage).join('；')}`;
  }
  if (cause instanceof BackupServiceError) {
    return `${stageLabel(cause.stage)}：${cause.message}`;
  }
  return `操作失败：${errorMessage(cause)}`;
}

function stageLabel(stage: BackupServiceError['stage']): string {
  switch (stage) {
    case 'select': return '选择文件失败';
    case 'archive': return '压缩包校验失败';
    case 'manifest': return '备份版本校验失败';
    case 'files': return '文件校验失败';
    case 'integrity': return '数据库完整性校验失败';
    case 'replace': return '替换数据失败';
    case 'share': return '分享失败';
    case 'cleanup': return '临时文件清理失败';
  }
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

const styles = StyleSheet.create({
  container: {
    borderColor: colors.border,
    borderTopWidth: 1,
    gap: spacing.md,
    paddingTop: spacing.lg,
  },
  heading: { color: colors.text, fontSize: 18, fontWeight: '700' },
  actions: { gap: spacing.sm },
  action: { borderRadius: radius.md, borderWidth: 1, padding: spacing.md },
  standardAction: { borderColor: colors.accent },
  dangerAction: { borderColor: colors.danger },
  disabled: { opacity: 0.45 },
  actionText: { color: colors.accent, fontSize: 16, fontWeight: '700' },
  dangerText: { color: colors.danger, fontSize: 16, fontWeight: '700' },
  confirmation: {
    backgroundColor: colors.card,
    borderColor: colors.border,
    borderRadius: radius.md,
    borderWidth: 1,
    gap: spacing.sm,
    padding: spacing.md,
  },
  warning: { color: colors.danger, fontSize: 15, fontWeight: '700' },
  help: { color: colors.text, fontSize: 14 },
  input: {
    borderColor: colors.border,
    borderRadius: radius.sm,
    borderWidth: 1,
    color: colors.text,
    fontSize: 16,
    padding: spacing.md,
  },
  confirmationActions: { flexDirection: 'row', gap: spacing.sm },
  message: { color: colors.muted, fontSize: 14 },
});

export default BackupActions;
