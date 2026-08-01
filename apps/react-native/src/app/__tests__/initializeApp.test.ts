import { createElement, useState } from 'react';
import { fireEvent, render, screen } from '@testing-library/react-native';
import { Text } from 'react-native';
import type { SQLiteDatabase } from 'expo-sqlite';

import { createDatabaseManager } from '../../data/database';
import type { SQLiteRepositories } from '../../data/repositories';
import type { BackupService } from '../../features/backup/backupService';
import type { MediaService } from '../../features/media/mediaService';
import { useBaby } from '../../features/baby/useBaby';
import { useRecordRepository } from '../../features/records/RecordRepositoryProvider';
import { MemoryBabyRepository, MemoryRecordRepository } from '../../test/memoryRepositories';
import { AppErrorBoundary } from '../AppErrorBoundary';
import { AppProvider, useAppServices, type AppServices } from '../AppProvider';
import { initializeApp } from '../initializeApp';
import { createMaintenanceCoordinator } from '../maintenance';

jest.mock('expo-sqlite', () => ({
  openDatabaseAsync: jest.fn(),
}));

test('initializes storage, database, cleanup, and stable services in dependency order', async () => {
  const events: string[] = [];
  const sqlite = {
    databasePath: '/documents/baby-growth.db',
    execAsync: jest.fn(async (sql: string) => {
      if (sql === 'PRAGMA foreign_keys = ON;') {
        events.push('migrate');
      }
    }),
    getFirstAsync: jest.fn(async () => ({ user_version: 1 })),
    closeAsync: jest.fn(async () => undefined),
  } as unknown as SQLiteDatabase;
  const database = createDatabaseManager('baby-growth.db', async () => {
    events.push('open-database');
    return sqlite;
  });
  const repositories = {
    babies: {
      get: jest.fn(async () => null),
    },
    records: {
      list: jest.fn(async () => []),
    },
    mediaReferences: {
      listReferencedMediaPaths: jest.fn(async () => {
        events.push('read-media-references');
        return [
          'file:///documents/media/avatar.jpg',
          'file:///documents/media/photo.jpg',
          'file:///documents/media/photo-thumb.jpg',
        ];
      }),
    },
  } as unknown as SQLiteRepositories;
  const media = {
    removeOrphans: jest.fn(async () => {
      events.push('remove-orphans');
    }),
  } as unknown as MediaService;
  const backup = {} as BackupService;
  const maintenance = createMaintenanceCoordinator();
  const repairMediaPaths = jest.fn(async () => {
    events.push('repair-media-paths');
  });

  const services = await initializeApp({
    database,
    media,
    mediaStorage: {
      ensureDirectories: async () => {
        events.push('ensure-directories');
      },
      clearStaging: async () => {
        events.push('clear-staging');
      },
    },
    repositoryFactory: () => repositories,
    backupFactory: () => backup,
    maintenance,
    repairMediaPaths,
  });
  events.push('return-services');

  expect(events).toEqual([
    'ensure-directories',
    'open-database',
    'migrate',
    'repair-media-paths',
    'clear-staging',
    'read-media-references',
    'remove-orphans',
    'return-services',
  ]);
  expect(repositories.babies.get).not.toHaveBeenCalled();
  expect(repositories.records.list).not.toHaveBeenCalled();
  expect(media.removeOrphans).toHaveBeenCalledWith([
    'file:///documents/media/avatar.jpg',
    'file:///documents/media/photo.jpg',
    'file:///documents/media/photo-thumb.jpg',
  ]);
  expect(services).toMatchObject({
    babies: repositories.babies,
    records: repositories.records,
    backup,
    database,
  });
  expect(services.media).toEqual(expect.objectContaining({
    stage: expect.any(Function),
    commit: expect.any(Function),
    rollback: expect.any(Function),
    remove: expect.any(Function),
    removeOrphans: expect.any(Function),
  }));
  services.reportCleanupWarning('记录已删除，媒体将在稍后清理');
  expect(maintenance.getSnapshot().warning).toBe('记录已删除，媒体将在稍后清理');
});

test('provides the same stable service instances to the app and feature consumers', async () => {
  const babies = new MemoryBabyRepository();
  const records = new MemoryRecordRepository();
  const media = {} as MediaService;
  const services: AppServices = {
    babies,
    records,
    media,
    backup: {} as BackupService,
    database: {} as AppServices['database'],
    reportCleanupWarning: jest.fn(),
  };

  function Consumer() {
    const app = useAppServices();
    const featureRecords = useRecordRepository();
    const babyState = useBaby();
    return createElement(
      Text,
      null,
      [
        app === services,
        app.media === media,
        featureRecords === records,
        babyState.loading,
      ].join(':'),
    );
  }

  await render(createElement(
    AppProvider,
    { services, children: createElement(Consumer) },
  ));

  expect(await screen.findByText('true:true:true:false')).toBeTruthy();
});

test('replaces a failed business tree and retries from a clean error boundary', async () => {
  const consoleError = jest.spyOn(console, 'error').mockImplementation(() => undefined);

  function FragileScreen({ fail }: { fail: boolean }) {
    if (fail) {
      throw new Error('render failed');
    }
    return createElement(Text, null, 'business-pages');
  }

  function Harness() {
    const [fail, setFail] = useState(true);
    return createElement(
      AppErrorBoundary,
      {
        onRetry: () => setFail(false),
        children: createElement(FragileScreen, { fail }),
      },
    );
  }

  try {
    await render(createElement(Harness));
    expect(await screen.findByText('无法打开本地数据')).toBeTruthy();
    expect(screen.queryByText('business-pages')).toBeNull();

    fireEvent.press(screen.getByRole('button', { name: '重试' }));

    expect(await screen.findByText('business-pages')).toBeTruthy();
    expect(screen.queryByText('无法打开本地数据')).toBeNull();
  } finally {
    consoleError.mockRestore();
  }
});
