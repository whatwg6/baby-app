import { openDatabaseAsync, type SQLiteDatabase } from 'expo-sqlite';

import { migrateDatabase } from './migrations';

export interface DatabaseManager {
  initialize(): Promise<SQLiteDatabase>;
  withClosedDatabase<T>(work: (databasePath: string) => Promise<T>): Promise<T>;
  withRecoveryJournal<T>(
    journal: RecoveryJournal,
    work: (context: RecoveryJournalContext) => Promise<T>,
  ): Promise<T>;
  reopen(): Promise<SQLiteDatabase>;
  markRecoveryRequired(cause: unknown): DatabaseRecoveryRequiredError;
  getLifecycleSnapshot(): DatabaseLifecycleSnapshot;
  subscribe(listener: () => void): () => void;
}

export interface RecoverySentinelStore {
  isRecoveryRequired(): boolean;
  markRecoveryRequired(journal?: RecoveryJournal): void;
  clearRecoveryRequired(): void;
}

export type RecoveryJournal = {
  operation: 'restore' | 'clear' | 'manual';
  operationId: string;
};

export type RecoveryJournalContext = {
  databasePath: string;
  reopen(): Promise<SQLiteDatabase>;
  closeReopened(): Promise<void>;
};

export type DatabaseLifecycleSnapshot =
  | { status: 'closed' }
  | { status: 'opening' }
  | { status: 'open'; database: SQLiteDatabase }
  | { status: 'closing'; database: SQLiteDatabase }
  | { status: 'recovery-required'; error: DatabaseRecoveryRequiredError };

export class DatabaseRecoveryRequiredError extends Error {
  constructor(
    message: string,
    readonly cause: unknown,
  ) {
    super(message);
    this.name = 'DatabaseRecoveryRequiredError';
  }
}

type OpenDatabase = (databaseName: string) => Promise<SQLiteDatabase>;

class ExpoDatabaseManager implements DatabaseManager {
  private database: SQLiteDatabase | null = null;
  private opening: Promise<SQLiteDatabase> | null = null;
  private lifecycleTail: Promise<void> = Promise.resolve();
  private lifecycleSnapshot: DatabaseLifecycleSnapshot = { status: 'closed' };
  private readonly listeners = new Set<() => void>();
  private recoveryRequired: DatabaseRecoveryRequiredError | null = null;
  private recoveryJournalActive = false;

  constructor(
    private readonly databaseName: string,
    private readonly openDatabase: OpenDatabase,
    private readonly recoverySentinel: RecoverySentinelStore,
  ) {}

  async initialize(): Promise<SQLiteDatabase> {
    return this.withLifecycle(() => this.initializeOpen());
  }

  async reopen(): Promise<SQLiteDatabase> {
    return this.withLifecycle(() => this.initializeOpen());
  }

  markRecoveryRequired(cause: unknown): DatabaseRecoveryRequiredError {
    let error = cause instanceof DatabaseRecoveryRequiredError
      ? cause
      : new DatabaseRecoveryRequiredError(
        'Local data recovery is required before the database can be reopened.',
        cause,
      );
    this.recoveryRequired = error;
    this.database = null;
    try {
      if (!this.recoveryJournalActive) {
        this.recoverySentinel.markRecoveryRequired({
          operation: 'manual',
          operationId: `manual-${Date.now()}`,
        });
      }
    } catch (sentinelError) {
      error = new DatabaseRecoveryRequiredError(
        'Local data recovery is required, but its persistent sentinel could not be written.',
        new AggregateError(
          [cause, sentinelError],
          'Recovery is required and sentinel persistence failed.',
        ),
      );
      this.recoveryRequired = error;
    }
    this.publish({ status: 'recovery-required', error });
    return error;
  }

  getLifecycleSnapshot = (): DatabaseLifecycleSnapshot => this.lifecycleSnapshot;

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

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
        this.publish({ status: 'closing', database });
        await database.execAsync('PRAGMA wal_checkpoint(TRUNCATE);');
        await database.closeAsync();
        closeCompleted = true;
        this.invalidateDatabase(database);
        this.publish({ status: 'closed' });
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
        this.publish({ status: 'closed' });
      }
      if (!(primaryError instanceof DatabaseRecoveryRequiredError) &&
          this.recoveryRequired === null) {
        try {
          await this.initializeOpen();
        } catch (reopenError) {
          cleanupErrors.push(reopenError);
        }
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

  async withRecoveryJournal<T>(
    journal: RecoveryJournal,
    work: (context: RecoveryJournalContext) => Promise<T>,
  ): Promise<T> {
    return this.withLifecycle(async () => {
      const current = await this.initializeOpen();
      await this.closeBeforeRecovery(current);

      try {
        this.recoverySentinel.markRecoveryRequired(journal);
        this.recoveryJournalActive = true;
      } catch (cause) {
        this.latchRecoveryRequired(new DatabaseRecoveryRequiredError(
          'The recovery journal could not be persisted; replacement work was aborted.',
          cause,
        ));
        throw cause;
      }

      let value: T | undefined;
      let completed = false;
      let primaryError: unknown;
      const reopen = async (): Promise<SQLiteDatabase> => {
        if (this.database !== null) {
          return this.database;
        }
        const reopened = await this.openAndMigrate();
        this.database = reopened;
        return reopened;
      };
      const closeReopened = async (): Promise<void> => {
        const reopened = this.database;
        if (reopened === null) {
          return;
        }
        try {
          await reopened.closeAsync();
        } finally {
          this.invalidateDatabase(reopened);
          this.publish({ status: 'closed' });
        }
      };

      try {
        value = await work({ closeReopened, databasePath: current.databasePath, reopen });
        completed = true;
      } catch (cause) {
        primaryError = cause;
      }

      if (this.database === null || this.recoveryRequired !== null) {
        if (this.recoveryRequired === null) {
          this.latchRecoveryRequired(new DatabaseRecoveryRequiredError(
            'Recovery work ended without a verified safe database reopen.',
            primaryError ?? new Error('Recovery work did not reopen the database.'),
          ));
        }
        if (primaryError !== undefined) {
          throw primaryError;
        }
        throw this.recoveryRequired;
      }

      const verifiedDatabase = this.database;
      try {
        this.recoverySentinel.clearRecoveryRequired();
      } catch (clearError) {
        let cause: unknown = clearError;
        try {
          await verifiedDatabase.closeAsync();
        } catch (closeError) {
          cause = new AggregateError(
            [clearError, closeError],
            'Recovery journal clearing and safe-handle closing both failed.',
          );
        }
        this.invalidateDatabase(verifiedDatabase);
        throw this.latchRecoveryRequired(new DatabaseRecoveryRequiredError(
          'Recovery completed, but its durable journal could not be cleared safely.',
          cause,
        ));
      }

      this.recoveryJournalActive = false;
      this.publish({ status: 'open', database: verifiedDatabase });
      if (primaryError !== undefined) {
        throw primaryError;
      }
      if (!completed) {
        throw new Error('Recovery work did not complete.');
      }
      return value as T;
    });
  }

  private async initializeOpen(): Promise<SQLiteDatabase> {
    if (this.recoveryRequired !== null) {
      throw this.recoveryRequired;
    }
    let sentinelRequired: boolean;
    try {
      sentinelRequired = this.recoverySentinel.isRecoveryRequired();
    } catch (cause) {
      throw this.latchRecoveryRequired(new DatabaseRecoveryRequiredError(
        'Local data recovery status could not be read; the database will remain closed.',
        cause,
      ));
    }
    if (sentinelRequired) {
      throw this.latchRecoveryRequired(new DatabaseRecoveryRequiredError(
        'Local data recovery is required before the database can be reopened.',
        new Error('Persistent recovery sentinel is present.'),
      ));
    }
    if (this.database !== null) {
      return this.database;
    }
    if (this.opening !== null) {
      return this.opening;
    }

    const opening = this.openAndMigrate();
    this.opening = opening;
    this.publish({ status: 'opening' });
    try {
      const database = await opening;
      this.database = database;
      this.publish({ status: 'open', database });
      return database;
    } catch (cause) {
      this.publish({ status: 'closed' });
      throw cause;
    } finally {
      if (this.opening === opening) {
        this.opening = null;
      }
    }
  }

  private async closeBeforeRecovery(database: SQLiteDatabase): Promise<void> {
    let primaryError: unknown;
    const cleanupErrors: unknown[] = [];
    this.publish({ status: 'closing', database });
    try {
      await database.execAsync('PRAGMA wal_checkpoint(TRUNCATE);');
      await database.closeAsync();
    } catch (cause) {
      primaryError = cause;
      try {
        await database.closeAsync();
      } catch (closeError) {
        cleanupErrors.push(closeError);
      }
    }
    this.invalidateDatabase(database);
    this.publish({ status: 'closed' });

    if (primaryError === undefined) {
      return;
    }
    try {
      await this.initializeOpen();
    } catch (reopenError) {
      cleanupErrors.push(reopenError);
    }
    if (cleanupErrors.length > 0) {
      throw new AggregateError(
        [primaryError, ...cleanupErrors],
        'Database could not be prepared for recovery work and lifecycle cleanup failed.',
      );
    }
    throw primaryError;
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

  private latchRecoveryRequired(
    error: DatabaseRecoveryRequiredError,
  ): DatabaseRecoveryRequiredError {
    this.recoveryRequired = error;
    this.database = null;
    this.publish({ status: 'recovery-required', error });
    return error;
  }

  private publish(snapshot: DatabaseLifecycleSnapshot): void {
    this.lifecycleSnapshot = snapshot;
    for (const listener of this.listeners) {
      listener();
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
  recoverySentinel: RecoverySentinelStore = createMemoryRecoverySentinelStore(),
): DatabaseManager {
  return new ExpoDatabaseManager(databaseName, openDatabase, recoverySentinel);
}

function createMemoryRecoverySentinelStore(): RecoverySentinelStore {
  let required = false;
  return {
    isRecoveryRequired: () => required,
    markRecoveryRequired: () => {
      required = true;
    },
    clearRecoveryRequired: () => {
      required = false;
    },
  };
}
