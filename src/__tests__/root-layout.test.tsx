import { act, render, screen, waitFor } from '@testing-library/react-native';
import type { SQLiteDatabase } from 'expo-sqlite';

import { DatabaseRoot } from '../../app/_layout';
import { createDatabaseManager } from '../data/database';
import type { SQLiteRepositories } from '../data/repositories';
import { MemoryBabyRepository, MemoryRecordRepository } from '../test/memoryRepositories';

jest.mock('expo-sqlite', () => ({
  openDatabaseAsync: jest.fn(),
}));

jest.mock('expo-router', () => {
  const { Text } = require('react-native') as typeof import('react-native');
  return { Stack: () => <Text>app-ready</Text> };
});

class LayoutDatabase {
  readonly databasePath = '/documents/baby-growth.db';
  closed = false;

  async execAsync(): Promise<void> {}

  async getFirstAsync<T>(): Promise<T> {
    return { user_version: 1 } as T;
  }

  async closeAsync(): Promise<void> {
    this.closed = true;
  }
}

function asSQLiteDatabase(database: LayoutDatabase): SQLiteDatabase {
  return database as unknown as SQLiteDatabase;
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
    return {
      babies: new MemoryBabyRepository(),
      records: new MemoryRecordRepository(),
    };
  });

  await render(
    <DatabaseRoot
      cleanupMedia={jest.fn(async () => undefined)}
      database={database}
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

test('renders a blocking recovery state without reopening partial files', async () => {
  const first = new LayoutDatabase();
  const openDatabase = jest
    .fn<Promise<SQLiteDatabase>, [string]>()
    .mockResolvedValueOnce(asSQLiteDatabase(first));
  const database = createDatabaseManager('baby-growth.db', openDatabase);

  await render(
    <DatabaseRoot
      cleanupMedia={jest.fn(async () => undefined)}
      database={database}
      repositoryFactory={() => ({
        babies: new MemoryBabyRepository(),
        records: new MemoryRecordRepository(),
      })}
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
});
