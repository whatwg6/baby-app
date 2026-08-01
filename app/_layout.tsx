import { useEffect, useMemo, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Stack } from 'expo-router';

import { createDatabaseManager, type DatabaseManager } from '../src/data/database';
import { createSQLiteRepositories, type SQLiteRepositories } from '../src/data/repositories';
import { BabyRepositoryProvider } from '../src/features/baby/useBaby';
import { BackupServiceProvider } from '../src/features/backup/BackupActions';
import { createBackupService } from '../src/features/backup/backupService';
import { mediaService, removeUnreferencedMedia } from '../src/features/media/mediaService';
import { RecordRepositoryProvider } from '../src/features/records/RecordRepositoryProvider';
import { colors, spacing } from '../src/ui/theme';

export default function RootLayout() {
  const databaseRef = useRef<DatabaseManager | null>(null);
  databaseRef.current ??= createDatabaseManager();
  return <DatabaseRoot database={databaseRef.current} />;
}

export function DatabaseRoot({
  database,
  repositoryFactory = createSQLiteRepositories,
  cleanupMedia = removeUnreferencedMedia,
}: {
  database: DatabaseManager;
  repositoryFactory?(database: Parameters<typeof createSQLiteRepositories>[0]): SQLiteRepositories;
  cleanupMedia?: typeof removeUnreferencedMedia;
}) {
  const [repositories, setRepositories] = useState<SQLiteRepositories | null>(null);
  const [failed, setFailed] = useState(false);
  const [recoveryRequired, setRecoveryRequired] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const backup = useMemo(() => repositories === null ? null : createBackupService({
    database,
    babies: repositories.babies,
    records: repositories.records,
    media: mediaService,
  }), [database, repositories]);

  useEffect(() => {
    let active = true;
    const applyLifecycle = () => {
      if (!active) {
        return;
      }
      const lifecycle = database.getLifecycleSnapshot();
      if (lifecycle.status === 'recovery-required') {
        setRepositories(null);
        setFailed(false);
        setRecoveryRequired(true);
        return;
      }
      if (lifecycle.status !== 'open') {
        setRepositories(null);
        setFailed(false);
        setRecoveryRequired(false);
        return;
      }

      const initialized = repositoryFactory(lifecycle.database);
      setRepositories(initialized);
      setFailed(false);
      setRecoveryRequired(false);
      void cleanupMedia({
        babies: initialized.babies,
        records: initialized.records,
        media: mediaService,
      })
        .catch(() => {
          if (active && database.getLifecycleSnapshot() === lifecycle) {
            setRepositories(null);
            setFailed(true);
          }
        });
    };
    const unsubscribe = database.subscribe(applyLifecycle);
    applyLifecycle();
    void database.initialize()
      .catch(() => {
        if (active && database.getLifecycleSnapshot().status !== 'recovery-required') {
          setRepositories(null);
          setFailed(true);
        }
      });

    return () => {
      active = false;
      unsubscribe();
    };
  }, [attempt, cleanupMedia, database, repositoryFactory]);

  if (repositories === null) {
    return (
      <View style={styles.startup}>
        <Text style={styles.startupText}>
          {recoveryRequired
            ? '本地数据恢复不完整，数据库已保持关闭'
            : failed ? '无法打开本地数据' : '正在准备宝宝成长记录…'}
        </Text>
        {failed && !recoveryRequired ? (
          <Pressable accessibilityRole="button" onPress={() => setAttempt((value) => value + 1)}>
            <Text style={styles.retry}>重试</Text>
          </Pressable>
        ) : null}
      </View>
    );
  }

  if (backup === null) {
    return null;
  }

  return (
    <BackupServiceProvider service={backup}>
      <BabyRepositoryProvider repository={repositories.babies}>
        <RecordRepositoryProvider repository={repositories.records}>
          <Stack screenOptions={{ headerShown: false }} />
        </RecordRepositoryProvider>
      </BabyRepositoryProvider>
    </BackupServiceProvider>
  );
}

const styles = StyleSheet.create({
  startup: {
    alignItems: 'center',
    backgroundColor: colors.background,
    flex: 1,
    gap: spacing.md,
    justifyContent: 'center',
    padding: spacing.lg,
  },
  startupText: { color: colors.text, fontSize: 16 },
  retry: { color: colors.accent, fontSize: 16, fontWeight: '700' },
});
