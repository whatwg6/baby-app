import { useEffect, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Stack } from 'expo-router';

import { AppErrorBoundary } from '../src/app/AppErrorBoundary';
import { AppProvider, type AppServices } from '../src/app/AppProvider';
import {
  assembleAppServices,
  initializeApp,
  type AppMediaStorage,
} from '../src/app/initializeApp';
import { createDatabaseManager, type DatabaseManager } from '../src/data/database';
import { createSQLiteRepositories, type SQLiteRepositories } from '../src/data/repositories';
import { mediaService, removeUnreferencedMedia, type MediaService } from '../src/features/media/mediaService';
import { colors, spacing } from '../src/ui/theme';

type BootstrapState =
  | { status: 'loading' }
  | { status: 'ready'; services: AppServices }
  | { status: 'error' }
  | { status: 'recovery-required' };

export default function RootLayout() {
  const databaseRef = useRef<DatabaseManager | null>(null);
  databaseRef.current ??= createDatabaseManager();
  return <DatabaseRoot database={databaseRef.current} />;
}

export function DatabaseRoot({
  database,
  repositoryFactory = createSQLiteRepositories,
  cleanupMedia = removeUnreferencedMedia,
  media = mediaService,
  mediaStorage,
}: {
  database: DatabaseManager;
  repositoryFactory?(database: Parameters<typeof createSQLiteRepositories>[0]): SQLiteRepositories;
  cleanupMedia?: typeof removeUnreferencedMedia;
  media?: MediaService;
  mediaStorage?: AppMediaStorage;
}) {
  const initialized = useRef(false);
  const [attempt, setAttempt] = useState(0);
  const [boundaryAttempt, setBoundaryAttempt] = useState(0);
  const [state, setState] = useState<BootstrapState>({ status: 'loading' });

  useEffect(() => {
    let active = true;
    initialized.current = false;

    const applyLifecycle = () => {
      if (!active) {
        return;
      }
      const lifecycle = database.getLifecycleSnapshot();
      if (lifecycle.status === 'recovery-required') {
        initialized.current = false;
        setState({ status: 'recovery-required' });
        return;
      }
      if (lifecycle.status !== 'open') {
        if (initialized.current) {
          setState({ status: 'loading' });
        }
        return;
      }
      if (!initialized.current) {
        return;
      }

      try {
        const repositories = repositoryFactory(lifecycle.database);
        const services = assembleAppServices({ database, media, repositories });
        setState({ status: 'ready', services });
      } catch {
        setState({ status: 'error' });
      }
    };

    const unsubscribe = database.subscribe(applyLifecycle);
    applyLifecycle();
    void initializeApp({
      database,
      media,
      mediaStorage,
      repositoryFactory,
      cleanupMedia,
    })
      .then((services) => {
        if (!active) {
          return;
        }
        initialized.current = true;
        setState({ status: 'ready', services });
      })
      .catch(() => {
        if (!active) {
          return;
        }
        initialized.current = false;
        setState(database.getLifecycleSnapshot().status === 'recovery-required'
          ? { status: 'recovery-required' }
          : { status: 'error' });
      });

    return () => {
      active = false;
      unsubscribe();
    };
  }, [attempt, cleanupMedia, database, media, mediaStorage, repositoryFactory]);

  if (state.status !== 'ready') {
    return (
      <LocalDataState
        onRetry={state.status === 'error'
          ? () => {
            setState({ status: 'loading' });
            setAttempt((value) => value + 1);
          }
          : undefined}
        status={state.status}
      />
    );
  }

  return (
    <AppErrorBoundary
      key={boundaryAttempt}
      onRetry={() => setBoundaryAttempt((value) => value + 1)}
    >
      <AppProvider services={state.services}>
        <Stack screenOptions={{ headerShown: false }} />
      </AppProvider>
    </AppErrorBoundary>
  );
}

function LocalDataState({
  status,
  onRetry,
}: {
  status: Exclude<BootstrapState['status'], 'ready'>;
  onRetry?: () => void;
}) {
  const message = status === 'recovery-required'
    ? '本地数据恢复不完整，数据库已保持关闭'
    : status === 'error' ? '无法打开本地数据' : '正在准备宝宝成长记录…';
  return (
    <View style={styles.startup}>
      <Text style={styles.startupText}>{message}</Text>
      {onRetry === undefined ? null : (
        <Pressable accessibilityRole="button" onPress={onRetry}>
          <Text style={styles.retry}>重试</Text>
        </Pressable>
      )}
    </View>
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
