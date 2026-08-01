import type { SQLiteDatabase } from 'expo-sqlite';

jest.mock('expo-sqlite', () => ({
  openDatabaseAsync: jest.fn(),
}));

import { createDatabaseManager } from '../database';
import { migrateDatabase } from '../migrations';

class MigrationDatabase {
  readonly databasePath = '/documents/baby-growth.db';
  readonly executed: string[] = [];
  closed = false;
  userVersion = 0;

  async execAsync(sql: string): Promise<void> {
    this.executed.push(sql);
    const version = sql.match(/PRAGMA user_version\s*=\s*(\d+)/i);
    if (version !== null) {
      this.userVersion = Number(version[1]);
    }
  }

  async getFirstAsync<T>(sql: string): Promise<T | null> {
    if (/PRAGMA user_version/i.test(sql)) {
      return { user_version: this.userVersion } as T;
    }
    return null;
  }

  async closeAsync(): Promise<void> {
    this.closed = true;
  }
}

function asSQLiteDatabase(database: MigrationDatabase): SQLiteDatabase {
  return database as unknown as SQLiteDatabase;
}

describe('migrateDatabase', () => {
  test('upgrades a fresh database to version 1 with constrained record tables', async () => {
    const database = new MigrationDatabase();

    await migrateDatabase(asSQLiteDatabase(database));

    expect(database.userVersion).toBe(1);
    expect(database.executed.join('\n')).toContain('PRAGMA foreign_keys = ON');
    expect(database.executed.join('\n')).toContain('CREATE TABLE IF NOT EXISTS records');
    expect(database.executed.join('\n')).toContain('CREATE TABLE IF NOT EXISTS growth_details');
    expect(database.executed.join('\n')).toContain('UNIQUE(record_id)');
    expect(database.executed.join('\n')).toContain('ON DELETE CASCADE');
    expect(database.executed.join('\n')).toContain('CREATE INDEX IF NOT EXISTS records_occurred_at_desc');
  });

  test('does not reapply version 1 after a database is already migrated', async () => {
    const database = new MigrationDatabase();
    database.userVersion = 1;

    await migrateDatabase(asSQLiteDatabase(database));

    expect(database.executed).toEqual(['PRAGMA foreign_keys = ON;']);
  });
});

describe('DatabaseManager.withClosedDatabase', () => {
  test('reopens and migrates the database even when the closed-database work fails', async () => {
    const first = new MigrationDatabase();
    const reopened = new MigrationDatabase();
    const openDatabase = jest
      .fn<Promise<SQLiteDatabase>, [string]>()
      .mockResolvedValueOnce(asSQLiteDatabase(first))
      .mockResolvedValueOnce(asSQLiteDatabase(reopened));
    const manager = createDatabaseManager('baby-growth.db', openDatabase);

    await expect(
      manager.withClosedDatabase(async (databasePath) => {
        expect(databasePath).toBe('/documents/baby-growth.db');
        throw new Error('copy failed');
      }),
    ).rejects.toThrow('copy failed');

    expect(first.executed).toContain('PRAGMA wal_checkpoint(TRUNCATE);');
    expect(first.closed).toBe(true);
    expect(openDatabase).toHaveBeenCalledTimes(2);
    expect(reopened.userVersion).toBe(1);
  });

  test('does not reopen the database while closed-database work owns its file', async () => {
    const first = new MigrationDatabase();
    const reopened = new MigrationDatabase();
    const openDatabase = jest
      .fn<Promise<SQLiteDatabase>, [string]>()
      .mockResolvedValueOnce(asSQLiteDatabase(first))
      .mockResolvedValueOnce(asSQLiteDatabase(reopened));
    const manager = createDatabaseManager('baby-growth.db', openDatabase);
    let startWork: (() => void) | undefined;
    let finishWork: (() => void) | undefined;
    const workStarted = new Promise<void>((resolve) => {
      startWork = resolve;
    });
    const finish = new Promise<void>((resolve) => {
      finishWork = resolve;
    });

    const closedWork = manager.withClosedDatabase(async () => {
      startWork?.();
      await finish;
    });
    await workStarted;

    const initializing = manager.initialize();
    expect(openDatabase).toHaveBeenCalledTimes(1);

    finishWork?.();
    await closedWork;
    await initializing;
    expect(openDatabase).toHaveBeenCalledTimes(2);
  });
});
