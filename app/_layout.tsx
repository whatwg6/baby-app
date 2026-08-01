import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
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
  const database = databaseRef.current;
  const [repositories, setRepositories] = useState<SQLiteRepositories | null>(null);
  const [failed, setFailed] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const reloadServices = useCallback(() => setAttempt((value) => value + 1), []);
  const backup = useMemo(() => repositories === null ? null : createBackupService({
    database,
    babies: repositories.babies,
    records: repositories.records,
    media: mediaService,
  }), [database, repositories]);

  useEffect(() => {
    let active = true;
    setRepositories(null);
    setFailed(false);

    void database.initialize()
      .then(async (database) => {
        const initialized = createSQLiteRepositories(database);
        await removeUnreferencedMedia({
          babies: initialized.babies,
          records: initialized.records,
          media: mediaService,
        });
        return initialized;
      })
      .then((initialized) => {
        if (active) {
          setRepositories(initialized);
        }
      })
      .catch(() => {
        if (active) {
          setFailed(true);
        }
      });

    return () => {
      active = false;
    };
  }, [attempt, database]);

  if (repositories === null) {
    return (
      <View style={styles.startup}>
        <Text style={styles.startupText}>{failed ? '无法打开本地数据' : '正在准备宝宝成长记录…'}</Text>
        {failed ? (
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
    <BackupServiceProvider onDataChanged={reloadServices} service={backup}>
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
