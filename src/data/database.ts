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

      try {
        await database.execAsync('PRAGMA wal_checkpoint(TRUNCATE);');
        await database.closeAsync();
        closeCompleted = true;
        this.invalidateDatabase(database);

        return await work(database.databasePath);
      } finally {
        this.invalidateDatabase(database);
        if (!closeCompleted) {
          try {
            await database.closeAsync();
          } catch {
            // The original checkpoint or close error is more actionable.
          }
        }
        await this.initializeOpen();
      }
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
    await migrateDatabase(database);
    return database;
  }
}

export function createDatabaseManager(
  databaseName = 'baby-growth-timeline.db',
  openDatabase: OpenDatabase = openDatabaseAsync,
): DatabaseManager {
  return new ExpoDatabaseManager(databaseName, openDatabase);
}
