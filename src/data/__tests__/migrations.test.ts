import type { SQLiteDatabase } from 'expo-sqlite';

jest.mock('expo-sqlite', () => ({
  openDatabaseAsync: jest.fn(),
}));

import {
  createDatabaseManager,
  type RecoverySentinelStore,
} from '../database';
import { migrateDatabase } from '../migrations';

interface MigrationDatabaseOptions {
  checkpointError?: Error;
  closeError?: Error;
  rollbackError?: Error;
  schemaFailures?: number;
}

class MigrationDatabase {
  readonly databasePath = '/documents/baby-growth.db';
  readonly executed: string[] = [];
  closed = false;
  userVersion = 0;
  closeCalls = 0;
  transactionActive = false;
  private schemaFailures: number;
  private transactionStartedSeparately = false;

  constructor(private readonly options: MigrationDatabaseOptions = {}) {
    this.schemaFailures = options.schemaFailures ?? 0;
  }

  async execAsync(sql: string): Promise<void> {
    this.executed.push(sql);
    if (this.closed) {
      throw new Error('database is closed');
    }
    if (/PRAGMA wal_checkpoint/i.test(sql) && this.options.checkpointError !== undefined) {
      throw this.options.checkpointError;
    }
    if (sql.includes('CREATE TABLE IF NOT EXISTS baby')) {
      if (this.transactionActive && !this.transactionStartedSeparately) {
        throw new Error('cannot start a transaction within a transaction');
      }
      if (!this.transactionActive) {
        this.transactionActive = true;
      }
      if (this.schemaFailures > 0) {
        this.schemaFailures -= 1;
        throw new Error('schema statement failed');
      }
      const version = sql.match(/PRAGMA user_version\s*=\s*(\d+)/i);
      if (version !== null) {
        this.userVersion = Number(version[1]);
      }
      if (!this.transactionStartedSeparately) {
        this.transactionActive = false;
      }
      return;
    }
    if (/^\s*BEGIN;/i.test(sql)) {
      if (this.transactionActive) {
        throw new Error('cannot start a transaction within a transaction');
      }
      this.transactionActive = true;
      this.transactionStartedSeparately = true;
      return;
    }
    if (/^\s*ROLLBACK;/i.test(sql)) {
      if (this.options.rollbackError !== undefined) {
        throw this.options.rollbackError;
      }
      this.transactionActive = false;
      this.transactionStartedSeparately = false;
      return;
    }
    if (/^\s*COMMIT;/i.test(sql)) {
      this.transactionActive = false;
      this.transactionStartedSeparately = false;
      return;
    }
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
    this.closeCalls += 1;
    this.closed = true;
    if (this.closeCalls === 1 && this.options.closeError !== undefined) {
      throw this.options.closeError;
    }
  }
}

class MemoryRecoverySentinelStore implements RecoverySentinelStore {
  required = false;
  readError: Error | null = null;
  writeError: Error | null = null;

  isRecoveryRequired = jest.fn(() => {
    if (this.readError !== null) {
      throw this.readError;
    }
    return this.required;
  });

  markRecoveryRequired = jest.fn(() => {
    if (this.writeError !== null) {
      throw this.writeError;
    }
    this.required = true;
  });
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

  test('rolls back a failed schema migration so the same connection can retry', async () => {
    const database = new MigrationDatabase({ schemaFailures: 1 });

    await expect(migrateDatabase(asSQLiteDatabase(database))).rejects.toThrow(
      'schema statement failed',
    );
    await expect(migrateDatabase(asSQLiteDatabase(database))).resolves.toBeUndefined();

    expect(database.transactionActive).toBe(false);
    expect(database.userVersion).toBe(1);
  });

  test('surfaces both schema and rollback failures', async () => {
    const rollbackError = new Error('rollback failed');
    const database = new MigrationDatabase({ schemaFailures: 1, rollbackError });

    await expect(migrateDatabase(asSQLiteDatabase(database))).rejects.toMatchObject({
      name: 'AggregateError',
      errors: expect.arrayContaining([
        expect.objectContaining({ message: 'schema statement failed' }),
        rollbackError,
      ]),
    });
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

  test('closes and reopens a fresh database after WAL checkpoint rejection', async () => {
    const checkpointError = new Error('checkpoint rejected');
    const first = new MigrationDatabase({ checkpointError });
    const reopened = new MigrationDatabase();
    const openDatabase = jest
      .fn<Promise<SQLiteDatabase>, [string]>()
      .mockResolvedValueOnce(asSQLiteDatabase(first))
      .mockResolvedValueOnce(asSQLiteDatabase(reopened));
    const manager = createDatabaseManager('baby-growth.db', openDatabase);
    let workRan = false;

    await expect(
      manager.withClosedDatabase(async () => {
        workRan = true;
      }),
    ).rejects.toThrow('checkpoint rejected');

    expect(workRan).toBe(false);
    expect(first.closed).toBe(true);
    expect(openDatabase).toHaveBeenCalledTimes(2);
    expect(await manager.initialize()).toBe(asSQLiteDatabase(reopened));
  });

  test('reopens a fresh database when close rejects after physically closing', async () => {
    const closeError = new Error('close rejected');
    const first = new MigrationDatabase({ closeError });
    const reopened = new MigrationDatabase();
    const openDatabase = jest
      .fn<Promise<SQLiteDatabase>, [string]>()
      .mockResolvedValueOnce(asSQLiteDatabase(first))
      .mockResolvedValueOnce(asSQLiteDatabase(reopened));
    const manager = createDatabaseManager('baby-growth.db', openDatabase);

    await expect(manager.withClosedDatabase(async () => undefined)).rejects.toThrow(
      'close rejected',
    );

    expect(first.closed).toBe(true);
    expect(first.closeCalls).toBe(2);
    expect(openDatabase).toHaveBeenCalledTimes(2);
    expect(await manager.initialize()).toBe(asSQLiteDatabase(reopened));
  });

  test('closes a newly opened handle when migration fails during reopen', async () => {
    const first = new MigrationDatabase();
    const migrationFailure = new MigrationDatabase({ schemaFailures: 1 });
    const openDatabase = jest
      .fn<Promise<SQLiteDatabase>, [string]>()
      .mockResolvedValueOnce(asSQLiteDatabase(first))
      .mockResolvedValueOnce(asSQLiteDatabase(migrationFailure));
    const manager = createDatabaseManager('baby-growth.db', openDatabase);

    await expect(manager.withClosedDatabase(async () => undefined)).rejects.toThrow(
      'schema statement failed',
    );

    expect(migrationFailure.closed).toBe(true);
  });

  test('surfaces a repeated close cleanup failure with the primary close error', async () => {
    const first = new MigrationDatabase();
    const firstCloseError = new Error('first close failed');
    const cleanupCloseError = new Error('cleanup close failed');
    first.closeAsync = jest.fn(async () => {
      first.closeCalls += 1;
      first.closed = true;
      throw first.closeCalls === 1 ? firstCloseError : cleanupCloseError;
    });
    const reopened = new MigrationDatabase();
    const openDatabase = jest
      .fn<Promise<SQLiteDatabase>, [string]>()
      .mockResolvedValueOnce(asSQLiteDatabase(first))
      .mockResolvedValueOnce(asSQLiteDatabase(reopened));
    const manager = createDatabaseManager('baby-growth.db', openDatabase);

    await expect(manager.withClosedDatabase(async () => undefined)).rejects.toMatchObject({
      name: 'AggregateError',
      errors: [firstCloseError, cleanupCloseError],
    });
  });

  test('keeps the database closed after closed work marks recovery as required', async () => {
    const first = new MigrationDatabase();
    const reopened = new MigrationDatabase();
    const openDatabase = jest
      .fn<Promise<SQLiteDatabase>, [string]>()
      .mockResolvedValueOnce(asSQLiteDatabase(first))
      .mockResolvedValueOnce(asSQLiteDatabase(reopened));
    const manager = createDatabaseManager('baby-growth.db', openDatabase);
    const rollbackFailure = new Error('old WAL could not be restored');

    await expect(manager.withClosedDatabase(async () => {
      throw manager.markRecoveryRequired(rollbackFailure);
    })).rejects.toMatchObject({
      name: 'DatabaseRecoveryRequiredError',
      cause: rollbackFailure,
    });

    expect(openDatabase).toHaveBeenCalledTimes(1);
    expect(manager.getLifecycleSnapshot()).toMatchObject({
      status: 'recovery-required',
    });
    await expect(manager.initialize()).rejects.toMatchObject({
      name: 'DatabaseRecoveryRequiredError',
    });
    expect(openDatabase).toHaveBeenCalledTimes(1);
  });

  test('blocks a fresh manager after another manager persists recovery-required', async () => {
    const store = new MemoryRecoverySentinelStore();
    const first = new MigrationDatabase();
    const firstOpen = jest.fn(async () => asSQLiteDatabase(first));
    const managerA = createDatabaseManager('baby-growth.db', firstOpen, store);

    await expect(managerA.withClosedDatabase(async () => {
      throw managerA.markRecoveryRequired(new Error('unsafe rollback'));
    })).rejects.toMatchObject({ name: 'DatabaseRecoveryRequiredError' });

    const secondOpen = jest.fn(async () => asSQLiteDatabase(new MigrationDatabase()));
    const managerB = createDatabaseManager('baby-growth.db', secondOpen, store);
    await expect(managerB.initialize()).rejects.toMatchObject({
      name: 'DatabaseRecoveryRequiredError',
    });

    expect(store.required).toBe(true);
    expect(store.markRecoveryRequired).toHaveBeenCalledTimes(1);
    expect(secondOpen).not.toHaveBeenCalled();
    expect(managerB.getLifecycleSnapshot()).toMatchObject({ status: 'recovery-required' });
  });

  test('fails closed before opening when the recovery sentinel cannot be read', async () => {
    const store = new MemoryRecoverySentinelStore();
    store.readError = new Error('sentinel read failed');
    const openDatabase = jest.fn(async () => asSQLiteDatabase(new MigrationDatabase()));
    const manager = createDatabaseManager('baby-growth.db', openDatabase, store);

    await expect(manager.initialize()).rejects.toMatchObject({
      name: 'DatabaseRecoveryRequiredError',
      cause: store.readError,
    });

    expect(openDatabase).not.toHaveBeenCalled();
    expect(manager.getLifecycleSnapshot()).toMatchObject({ status: 'recovery-required' });
    await expect(manager.reopen()).rejects.toMatchObject({
      name: 'DatabaseRecoveryRequiredError',
    });
    expect(openDatabase).not.toHaveBeenCalled();
  });

  test('fails closed without reopening when the recovery sentinel cannot be written', async () => {
    const store = new MemoryRecoverySentinelStore();
    store.writeError = new Error('sentinel write failed');
    const first = new MigrationDatabase();
    const openDatabase = jest.fn(async () => asSQLiteDatabase(first));
    const manager = createDatabaseManager('baby-growth.db', openDatabase, store);

    await expect(manager.withClosedDatabase(async () => {
      throw manager.markRecoveryRequired(new Error('unsafe rollback'));
    })).rejects.toMatchObject({
      name: 'DatabaseRecoveryRequiredError',
      cause: expect.objectContaining({ name: 'AggregateError' }),
    });

    expect(store.markRecoveryRequired).toHaveBeenCalledTimes(1);
    expect(openDatabase).toHaveBeenCalledTimes(1);
    expect(manager.getLifecycleSnapshot()).toMatchObject({ status: 'recovery-required' });
    await expect(manager.initialize()).rejects.toMatchObject({
      name: 'DatabaseRecoveryRequiredError',
    });
    expect(openDatabase).toHaveBeenCalledTimes(1);
  });

  test('publishes closed lifecycle boundaries and the fresh handle before work resolves', async () => {
    const first = new MigrationDatabase();
    const reopened = new MigrationDatabase();
    const openDatabase = jest
      .fn<Promise<SQLiteDatabase>, [string]>()
      .mockResolvedValueOnce(asSQLiteDatabase(first))
      .mockResolvedValueOnce(asSQLiteDatabase(reopened));
    const manager = createDatabaseManager('baby-growth.db', openDatabase);
    const events: string[] = [];
    manager.subscribe(() => {
      const snapshot = manager.getLifecycleSnapshot();
      events.push(snapshot.status === 'open'
        ? `open:${snapshot.database === asSQLiteDatabase(reopened) ? 'fresh' : 'initial'}`
        : snapshot.status);
    });

    await manager.initialize();
    events.length = 0;
    await manager.withClosedDatabase(async () => {
      events.push('closed-work');
    });
    events.push('service-continued');

    expect(events).toEqual([
      'closing',
      'closed',
      'closed-work',
      'opening',
      'open:fresh',
      'service-continued',
    ]);
  });
});
