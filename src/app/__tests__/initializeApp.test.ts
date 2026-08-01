import { createElement, useState } from 'react';
import { fireEvent, render, screen } from '@testing-library/react-native';
import { Text } from 'react-native';
import type { SQLiteDatabase } from 'expo-sqlite';

import { createDatabaseManager } from '../../data/database';
import type { SQLiteRepositories } from '../../data/repositories';
import type { Baby, TimelineRecord } from '../../domain/types';
import type { BackupService } from '../../features/backup/backupService';
import type { MediaService } from '../../features/media/mediaService';
import { useBaby } from '../../features/baby/useBaby';
import { useRecordRepository } from '../../features/records/RecordRepositoryProvider';
import { MemoryBabyRepository, MemoryRecordRepository } from '../../test/memoryRepositories';
import { AppErrorBoundary } from '../AppErrorBoundary';
import { AppProvider, useAppServices, type AppServices } from '../AppProvider';
import { initializeApp } from '../initializeApp';

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
  const baby = { avatarPath: 'file:///documents/media/avatar.jpg' } as Baby;
  const record = {
    attachments: [{
      filePath: 'file:///documents/media/photo.jpg',
      thumbnailPath: 'file:///documents/media/photo-thumb.jpg',
    }],
  } as TimelineRecord;
  const repositories = {
    babies: {
      get: jest.fn(async () => {
        events.push('read-baby');
        return baby;
      }),
    },
    records: {
      list: jest.fn(async () => {
        events.push('read-records');
        return [record];
      }),
    },
  } as unknown as SQLiteRepositories;
  const media = {
    removeOrphans: jest.fn(async () => {
      events.push('remove-orphans');
    }),
  } as unknown as MediaService;
  const backup = {} as BackupService;

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
  });
  events.push('return-services');

  expect(events).toEqual([
    'ensure-directories',
    'open-database',
    'migrate',
    'clear-staging',
    'read-baby',
    'read-records',
    'remove-orphans',
    'return-services',
  ]);
  expect(media.removeOrphans).toHaveBeenCalledWith([
    'file:///documents/media/avatar.jpg',
    'file:///documents/media/photo.jpg',
    'file:///documents/media/photo-thumb.jpg',
  ]);
  expect(services).toEqual({
    babies: repositories.babies,
    records: repositories.records,
    media,
    backup,
    database,
  });
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
