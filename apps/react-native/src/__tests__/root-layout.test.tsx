import { act, fireEvent, render, screen, waitFor } from '@testing-library/react-native';
import type { SQLiteDatabase } from 'expo-sqlite';

import { DatabaseRoot } from '../../app/_layout';
import {
  createDatabaseManager,
  type RecoverySentinelStore,
} from '../data/database';
import type { SQLiteRepositories } from '../data/repositories';
import type { AppMediaStorage } from '../app/initializeApp';
import { createMaintenanceCoordinator } from '../app/maintenance';
import { MemoryBabyRepository, MemoryRecordRepository } from '../test/memoryRepositories';

jest.mock('expo-sqlite', () => ({
  openDatabaseAsync: jest.fn(),
}));

jest.mock('expo-router', () => {
  const { Text } = require('react-native') as typeof import('react-native');
  return {
    Stack: () => {
      const { useAppServices } = require('../app/AppProvider') as typeof import('../app/AppProvider');
      const services = useAppServices();
      return <Text>{services.database === undefined ? 'missing-services' : 'app-ready'}</Text>;
    },
  };
});

const mediaStorage: AppMediaStorage = {
  ensureDirectories: jest.fn(async () => undefined),
  clearStaging: jest.fn(async () => undefined),
};

class LayoutDatabase {
  readonly databasePath = '/documents/baby-growth.db';
  closed = false;

  async execAsync(_sql?: string): Promise<void> {}

  async getFirstAsync<T>(): Promise<T> {
    return { user_version: 1 } as T;
  }

  async getAllAsync<T>(): Promise<T[]> {
    return [];
  }

  async withExclusiveTransactionAsync(
    work: (transaction: SQLiteDatabase) => Promise<void>,
  ): Promise<void> {
    await work(asSQLiteDatabase(this));
  }

  async closeAsync(): Promise<void> {
    this.closed = true;
  }
}

function asSQLiteDatabase(database: LayoutDatabase): SQLiteDatabase {
  return database as unknown as SQLiteDatabase;
}

function memoryRepositories(): SQLiteRepositories {
  return {
    babies: new MemoryBabyRepository(),
    records: new MemoryRecordRepository(),
    mediaReferences: {
      listReferencedMediaPaths: jest.fn(async () => []),
    },
  };
}

test('removes stale providers while closed and installs fresh repositories before work continues', async () => {
  const first = new LayoutDatabase();
  const reopened = new LayoutDatabase();
  const openDatabase = jest
    .fn<Promise<SQLiteDatabase>, [string]>()
    .mockResolvedValueOnce(asSQLiteDatabase(first))
    .mockResolvedValueOnce(asSQLiteDatabase(reopened));
  const database = createDatabaseManager('baby-growth.db', openDatabase);
  const events: string[] = [];
  const repositoryFactory = jest.fn((handle: SQLiteDatabase): SQLiteRepositories => {
    events.push(handle === asSQLiteDatabase(first) ? 'repositories:first' : 'repositories:fresh');
    return memoryRepositories();
  });

  await render(
    <DatabaseRoot
      cleanupMedia={jest.fn(async () => undefined)}
      database={database}
      mediaStorage={mediaStorage}
      repositoryFactory={repositoryFactory}
    />,
  );
  await screen.findByText('app-ready');

  let releaseWork: (() => void) | undefined;
  let markWorkStarted: (() => void) | undefined;
  const holdWork = new Promise<void>((resolve) => {
    releaseWork = resolve;
  });
  const workStarted = new Promise<void>((resolve) => {
    markWorkStarted = resolve;
  });
  let closedWork!: Promise<void>;
  await act(async () => {
    closedWork = database.withClosedDatabase(async () => {
      events.push('closed-work');
      markWorkStarted?.();
      await holdWork;
    }).then(() => {
      events.push('service-continued');
    });
    await workStarted;
  });

  await waitFor(() => {
    expect(screen.queryByText('app-ready')).toBeNull();
    expect(screen.getByText('正在准备宝宝成长记录…')).toBeTruthy();
  });

  await act(async () => {
    releaseWork?.();
    await closedWork;
  });
  await screen.findByText('app-ready');

  expect(events).toEqual([
    'repositories:first',
    'closed-work',
    'repositories:fresh',
    'service-continued',
  ]);
  expect(repositoryFactory).toHaveBeenCalledTimes(2);
});

test('globally hides business routes during clear and preserves its warning after remount', async () => {
  const databaseHandle = new LayoutDatabase();
  const database = createDatabaseManager(
    'baby-growth.db',
    jest.fn(async () => asSQLiteDatabase(databaseHandle)),
  );
  const maintenance = createMaintenanceCoordinator();

  await render(
    <DatabaseRoot
      cleanupMedia={jest.fn(async () => undefined)}
      database={database}
      maintenance={maintenance}
      mediaStorage={mediaStorage}
      repositoryFactory={memoryRepositories}
    />,
  );
  await screen.findByText('app-ready');

  let lease!: ReturnType<typeof maintenance.begin>;
  await act(async () => {
    lease = maintenance.begin('clear');
  });
  expect(screen.queryByText('app-ready')).toBeNull();
  expect(screen.getByText('正在维护本地数据…')).toBeTruthy();

  await act(async () => {
    lease.finish({ warning: '旧媒体被系统锁定' });
  });
  expect(await screen.findByText('app-ready')).toBeTruthy();
  expect(screen.getByText('旧媒体被系统锁定')).toBeTruthy();
});

test('renders a blocking recovery state without reopening partial files', async () => {
  let recoveryRequired = false;
  const recoveryStore: RecoverySentinelStore = {
    isRecoveryRequired: jest.fn(() => recoveryRequired),
    markRecoveryRequired: jest.fn(() => {
      recoveryRequired = true;
    }),
    clearRecoveryRequired: jest.fn(() => {
      recoveryRequired = false;
    }),
  };
  const first = new LayoutDatabase();
  const openDatabase = jest
    .fn<Promise<SQLiteDatabase>, [string]>()
    .mockResolvedValueOnce(asSQLiteDatabase(first));
  const database = createDatabaseManager('baby-growth.db', openDatabase, recoveryStore);

  const mounted = await render(
    <DatabaseRoot
      cleanupMedia={jest.fn(async () => undefined)}
      database={database}
      mediaStorage={mediaStorage}
      repositoryFactory={memoryRepositories}
    />,
  );
  await screen.findByText('app-ready');

  await act(async () => {
    await expect(database.withClosedDatabase(async () => {
      throw database.markRecoveryRequired(new Error('rollback incomplete'));
    })).rejects.toMatchObject({ name: 'DatabaseRecoveryRequiredError' });
  });

  expect(await screen.findByText('本地数据恢复不完整，数据库已保持关闭')).toBeTruthy();
  expect(screen.queryByRole('button', { name: '重试' })).toBeNull();
  expect(openDatabase).toHaveBeenCalledTimes(1);
  expect(recoveryStore.markRecoveryRequired).toHaveBeenCalledTimes(1);

  await act(async () => {
    mounted.unmount();
  });
  const restartedOpen = jest.fn(async () => asSQLiteDatabase(new LayoutDatabase()));
  const restartedDatabase = createDatabaseManager(
    'baby-growth.db',
    restartedOpen,
    recoveryStore,
  );
  await render(
    <DatabaseRoot
      cleanupMedia={jest.fn(async () => undefined)}
      database={restartedDatabase}
      mediaStorage={mediaStorage}
      repositoryFactory={memoryRepositories}
    />,
  );

  expect(await screen.findByText('本地数据恢复不完整，数据库已保持关闭')).toBeTruthy();
  expect(screen.queryByRole('button', { name: '重试' })).toBeNull();
  expect(screen.queryByText('app-ready')).toBeNull();
  expect(restartedOpen).not.toHaveBeenCalled();
});

test('keeps business routes unmounted when migration fails and retries initialization', async () => {
  const failed = new LayoutDatabase();
  failed.execAsync = async (sql?: string) => {
    if (sql === 'PRAGMA foreign_keys = ON;') {
      throw new Error('migration failed');
    }
  };
  const reopened = new LayoutDatabase();
  const openDatabase = jest
    .fn<Promise<SQLiteDatabase>, [string]>()
    .mockResolvedValueOnce(asSQLiteDatabase(failed))
    .mockResolvedValueOnce(asSQLiteDatabase(reopened));
  const database = createDatabaseManager('baby-growth.db', openDatabase);

  await render(
    <DatabaseRoot
      cleanupMedia={jest.fn(async () => undefined)}
      database={database}
      mediaStorage={mediaStorage}
      repositoryFactory={memoryRepositories}
    />,
  );

  expect(await screen.findByText('无法打开本地数据')).toBeTruthy();
  expect(screen.queryByText('app-ready')).toBeNull();
  expect(failed.closed).toBe(true);

  await act(async () => {
    fireEvent.press(screen.getByRole('button', { name: '重试' }));
  });

  expect(await screen.findByText('app-ready')).toBeTruthy();
  expect(openDatabase).toHaveBeenCalledTimes(2);
});
