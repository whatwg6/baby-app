import { openDatabaseAsync, type SQLiteDatabase } from 'expo-sqlite';

import { migrateDatabase } from './migrations';

export interface DatabaseManager {
  initialize(): Promise<SQLiteDatabase>;
  withClosedDatabase<T>(work: (databasePath: string) => Promise<T>): Promise<T>;
  reopen(): Promise<SQLiteDatabase>;
}

type OpenDatabase = (databaseName: string) => Promise<SQLiteDatabase>;

class ExpoDatabaseManager implements DatabaseManager {
  private database: SQLiteDatabase | null = null;
  private opening: Promise<SQLiteDatabase> | null = null;
  private lifecycleTail: Promise<void> = Promise.resolve();

  constructor(
    private readonly databaseName: string,
    private readonly openDatabase: OpenDatabase,
  ) {}

  async initialize(): Promise<SQLiteDatabase> {
    return this.withLifecycle(() => this.initializeOpen());
  }

  async reopen(): Promise<SQLiteDatabase> {
    return this.withLifecycle(() => this.initializeOpen());
  }

  async withClosedDatabase<T>(
    work: (databasePath: string) => Promise<T>,
  ): Promise<T> {
    return this.withLifecycle(async () => {
      const database = await this.initializeOpen();
      let closeCompleted = false;
      let value: T | undefined;
      let workCompleted = false;
      let primaryError: unknown;
      const cleanupErrors: unknown[] = [];

      try {
        await database.execAsync('PRAGMA wal_checkpoint(TRUNCATE);');
        await database.closeAsync();
        closeCompleted = true;
        this.invalidateDatabase(database);
        value = await work(database.databasePath);
        workCompleted = true;
      } catch (cause) {
        primaryError = cause;
      }

      this.invalidateDatabase(database);
      if (!closeCompleted) {
        try {
          await database.closeAsync();
        } catch (closeError) {
          cleanupErrors.push(closeError);
        }
      }
      try {
        await this.initializeOpen();
      } catch (reopenError) {
        cleanupErrors.push(reopenError);
      }

      if (primaryError !== undefined) {
        if (cleanupErrors.length > 0) {
          throw new AggregateError(
            [primaryError, ...cleanupErrors],
            'Closed-database work failed and lifecycle recovery was incomplete.',
          );
        }
        throw primaryError;
      }
      if (cleanupErrors.length === 1) {
        throw cleanupErrors[0];
      }
      if (cleanupErrors.length > 1) {
        throw new AggregateError(
          cleanupErrors,
          'Database lifecycle recovery was incomplete.',
        );
      }
      if (!workCompleted) {
        throw new Error('Closed-database work did not complete.');
      }
      return value as T;
    });
  }

  private async initializeOpen(): Promise<SQLiteDatabase> {
    if (this.database !== null) {
      return this.database;
    }
    if (this.opening !== null) {
      return this.opening;
    }

    const opening = this.openAndMigrate();
    this.opening = opening;
    try {
      const database = await opening;
      this.database = database;
      return database;
    } finally {
      if (this.opening === opening) {
        this.opening = null;
      }
    }
  }

  private async withLifecycle<T>(work: () => Promise<T>): Promise<T> {
    const previous = this.lifecycleTail;
    let release: (() => void) | undefined;
    this.lifecycleTail = new Promise<void>((resolve) => {
      release = resolve;
    });

    await previous;
    try {
      return await work();
    } finally {
      release?.();
    }
  }

  private invalidateDatabase(database: SQLiteDatabase): void {
    if (this.database === database) {
      this.database = null;
    }
  }

  private async openAndMigrate(): Promise<SQLiteDatabase> {
    const database = await this.openDatabase(this.databaseName);
    try {
      await migrateDatabase(database);
      return database;
    } catch (migrationError) {
      try {
        await database.closeAsync();
      } catch (closeError) {
        throw new AggregateError(
          [migrationError, closeError],
          'Database migration failed and the new connection could not be closed.',
        );
      }
      throw migrationError;
    }
  }
}

export function createDatabaseManager(
  databaseName = 'baby-growth-timeline.db',
  openDatabase: OpenDatabase = openDatabaseAsync,
): DatabaseManager {
  return new ExpoDatabaseManager(databaseName, openDatabase);
}
