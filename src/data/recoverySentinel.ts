import { Directory, File, Paths } from 'expo-file-system';
import {
  defaultDatabaseDirectory,
  openDatabaseSync,
  type SQLiteDatabase,
} from 'expo-sqlite';

import type { RecoveryJournal, RecoverySentinelStore } from './database';

const LEGACY_RECOVERY_SENTINEL_FILE = 'baby-growth-recovery-required.json';
const RECOVERY_JOURNAL_DATABASE = 'baby-growth-recovery-journal.db';

type RecoveryJournalDatabase = Pick<
  SQLiteDatabase,
  'execSync' | 'getFirstSync' | 'runSync' | 'withTransactionSync'
>;

type OpenRecoveryJournalDatabase = (documentDirectory: string) => RecoveryJournalDatabase;

type StoredRecoveryJournal = {
  operation: RecoveryJournal['operation'];
  operationId: string;
};

export function createExpoRecoverySentinelStore(
  documentDirectory = Paths.document.uri,
  openJournalDatabase: OpenRecoveryJournalDatabase = (directory) => (
    openDatabaseSync(RECOVERY_JOURNAL_DATABASE, undefined, directory)
  ),
): RecoverySentinelStore {
  const documents = new Directory(documentDirectory);
  const legacySentinel = new File(appendPath(
    documentDirectory,
    LEGACY_RECOVERY_SENTINEL_FILE,
  ));
  const journalDatabases = new Map<string, RecoveryJournalDatabase>();
  const getJournalDatabase = (directory: string): RecoveryJournalDatabase => {
    const existing = journalDatabases.get(directory);
    if (existing !== undefined) {
      return existing;
    }
    // Keep one barrier beside each independently renamed file set. With
    // synchronous=EXTRA, each transaction also syncs that directory's entry.
    const opened = openJournalDatabase(directory);
      opened.execSync(`
        PRAGMA journal_mode = DELETE;
        PRAGMA synchronous = EXTRA;
        PRAGMA fullfsync = ON;
        CREATE TABLE IF NOT EXISTS recovery_journal (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          operation TEXT NOT NULL CHECK (operation IN ('restore', 'clear', 'manual')),
          operation_id TEXT NOT NULL,
          created_at TEXT NOT NULL
        );
      `);
    journalDatabases.set(directory, opened);
    return opened;
  };
  const primaryJournal = () => getJournalDatabase(defaultDatabaseDirectory);
  const mediaJournal = () => getJournalDatabase(documentDirectory);

  const readJournal = (database: RecoveryJournalDatabase): StoredRecoveryJournal | null => (
    database.getFirstSync<StoredRecoveryJournal>(`
      SELECT operation, operation_id AS operationId
      FROM recovery_journal
      WHERE singleton = 1;
    `)
  );

  const writeJournal = (
    database: RecoveryJournalDatabase,
    journal: RecoveryJournal,
  ): void => {
    database.withTransactionSync(() => {
      database.runSync(`
        INSERT INTO recovery_journal (
          singleton, operation, operation_id, created_at
        ) VALUES (1, ?, ?, ?)
        ON CONFLICT(singleton) DO UPDATE SET
          operation = excluded.operation,
          operation_id = excluded.operation_id,
          created_at = excluded.created_at;
      `, journal.operation, journal.operationId, new Date().toISOString());
    });
    const persisted = readJournal(database);
    if (persisted?.operation !== journal.operation ||
        persisted.operationId !== journal.operationId) {
      throw new Error('Recovery journal was not visible after its durable commit.');
    }
  };

  const clearJournal = (database: RecoveryJournalDatabase): void => {
    database.withTransactionSync(() => {
      database.runSync('DELETE FROM recovery_journal WHERE singleton = 1;');
    });
  };

  return {
    isRecoveryRequired: () => {
      // Read both barriers before allowing startup. Any read/open uncertainty
      // throws and is converted by DatabaseManager into fail-closed recovery.
      const primaryStored = readJournal(primaryJournal());
      const mediaStored = readJournal(mediaJournal());
      if (primaryStored !== null || mediaStored !== null) {
        return true;
      }
      return documents
        .list()
        .some((entry) => entry.name === LEGACY_RECOVERY_SENTINEL_FILE);
    },
    markRecoveryRequired: (journal = {
      operation: 'manual' as const,
      operationId: `manual-${Date.now()}`,
    }) => {
      // The primary barrier is armed first and intentionally retained if the
      // Documents barrier cannot be committed or verified.
      writeJournal(primaryJournal(), journal);
      writeJournal(mediaJournal(), journal);
    },
    clearRecoveryRequired: () => {
      // Retire the legacy marker while the SQLite journal still blocks a
      // restart. The durable SQLite delete is the final fallible operation.
      const legacyMarkerVisible = documents
        .list()
        .some((entry) => entry.name === LEGACY_RECOVERY_SENTINEL_FILE);
      if (legacySentinel.exists || legacyMarkerVisible) {
        legacySentinel.delete();
      }

      // Documents clears first; the primary SQLite barrier is the final
      // unblock. A Documents clear failure therefore leaves primary armed.
      clearJournal(mediaJournal());
      clearJournal(primaryJournal());
    },
  };
}

function appendPath(directory: string, name: string): string {
  return `${directory.replace(/\/+$/, '')}/${name}`;
}
