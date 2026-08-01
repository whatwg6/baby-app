import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Stack } from 'expo-router';

import { createDatabaseManager } from '../src/data/database';
import { createSQLiteRepositories, type BabyRepository } from '../src/data/repositories';
import { BabyRepositoryProvider } from '../src/features/baby/useBaby';
import { colors, spacing } from '../src/ui/theme';

export default function RootLayout() {
  const [repository, setRepository] = useState<BabyRepository | null>(null);
  const [failed, setFailed] = useState(false);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let active = true;
    setRepository(null);
    setFailed(false);

    void createDatabaseManager()
      .initialize()
      .then((database) => {
        if (active) {
          setRepository(createSQLiteRepositories(database).babies);
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
  }, [attempt]);

  if (repository === null) {
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

  return (
    <BabyRepositoryProvider repository={repository}>
      <Stack screenOptions={{ headerShown: false }} />
    </BabyRepositoryProvider>
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
