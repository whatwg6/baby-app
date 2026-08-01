import type { SQLiteDatabase } from 'expo-sqlite';

import { repairMediaPaths } from '../../../data/mediaPathMigration';
import { rebaseLegacyPrivateMediaPath } from '../mediaPaths';

const currentMediaRoot =
  'file:///Users/test/Library/Developer/CoreSimulator/Devices/device/data/Containers/Data/Application/NEW/Documents/media';

test('rebases media from a previous iOS application container', () => {
  expect(rebaseLegacyPrivateMediaPath(
    'file:///Users/test/Library/Developer/CoreSimulator/Devices/device/data/Containers/Data/Application/OLD/Documents/media/photo.heic',
    currentMediaRoot,
  )).toBe(`${currentMediaRoot}/photo.heic`);
});

test('keeps current private media paths unchanged', () => {
  expect(rebaseLegacyPrivateMediaPath(
    `${currentMediaRoot}/photo.heic`,
    currentMediaRoot,
  )).toBe(`${currentMediaRoot}/photo.heic`);
});

test('continues to reject paths outside an iOS Documents media directory', () => {
  expect(() => rebaseLegacyPrivateMediaPath(
    'file:///tmp/photo.heic',
    currentMediaRoot,
  )).toThrow('媒体路径不安全');
  expect(() => rebaseLegacyPrivateMediaPath(
    'file:///Users/test/OLD/Documents/staging/photo.heic',
    currentMediaRoot,
  )).toThrow('媒体路径不安全');
});

test('repairs baby and attachment paths in one database transaction', async () => {
  const runAsync = jest.fn(async () => ({ changes: 1 }));
  const transaction = {
    getAllAsync: jest.fn(async (sql: string) => {
      if (sql.includes('FROM baby')) {
        return [{
          id: 'baby-1',
          path: 'file:///old/container/Documents/media/avatar.jpg',
        }];
      }
      return [{
        id: 'attachment-1',
        filePath: 'file:///old/container/Documents/media/photo.heic',
        thumbnailPath: 'file:///old/container/Documents/media/photo-thumb.jpg',
      }];
    }),
    runAsync,
  } as unknown as SQLiteDatabase;
  const withExclusiveTransactionAsync = jest.fn(async (
    work: (database: SQLiteDatabase) => Promise<void>,
  ): Promise<void> => work(transaction));
  const database = { withExclusiveTransactionAsync } as unknown as SQLiteDatabase;

  await repairMediaPaths(database, currentMediaRoot);

  expect(withExclusiveTransactionAsync).toHaveBeenCalledTimes(1);
  expect(runAsync).toHaveBeenNthCalledWith(
    1,
    expect.stringContaining('UPDATE baby'),
    [`${currentMediaRoot}/avatar.jpg`, 'baby-1'],
  );
  expect(runAsync).toHaveBeenNthCalledWith(
    2,
    expect.stringContaining('UPDATE attachments'),
    [
      `${currentMediaRoot}/photo.heic`,
      `${currentMediaRoot}/photo-thumb.jpg`,
      'attachment-1',
    ],
  );
});
