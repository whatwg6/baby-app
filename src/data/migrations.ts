import type { SQLiteDatabase } from 'expo-sqlite';

const LATEST_DATABASE_VERSION = 1;

const VERSION_1_SCHEMA = `
  CREATE TABLE IF NOT EXISTS baby (
    singleton INTEGER PRIMARY KEY NOT NULL CHECK (singleton = 1),
    id TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    birth_date TEXT NOT NULL,
    sex TEXT CHECK (sex IN ('female', 'male') OR sex IS NULL),
    avatar_path TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS records (
    id TEXT PRIMARY KEY NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('moment', 'growth', 'activity', 'milestone')),
    occurred_at TEXT NOT NULL,
    note TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );

  CREATE INDEX IF NOT EXISTS records_occurred_at_desc
    ON records (occurred_at DESC);

  CREATE TABLE IF NOT EXISTS growth_details (
    record_id TEXT NOT NULL REFERENCES records(id) ON DELETE CASCADE,
    height_cm REAL,
    weight_kg REAL,
    head_cm REAL,
    UNIQUE(record_id)
  );

  CREATE TABLE IF NOT EXISTS activity_details (
    record_id TEXT NOT NULL REFERENCES records(id) ON DELETE CASCADE,
    activity_type TEXT NOT NULL CHECK (activity_type IN ('feeding', 'sleep', 'diaper')),
    amount REAL,
    duration_minutes REAL,
    UNIQUE(record_id)
  );

  CREATE TABLE IF NOT EXISTS milestone_details (
    record_id TEXT NOT NULL REFERENCES records(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    preset_key TEXT,
    UNIQUE(record_id)
  );

  CREATE TABLE IF NOT EXISTS attachments (
    id TEXT PRIMARY KEY NOT NULL,
    record_id TEXT NOT NULL REFERENCES records(id) ON DELETE CASCADE,
    media_type TEXT NOT NULL CHECK (media_type IN ('image', 'video')),
    file_path TEXT NOT NULL,
    thumbnail_path TEXT,
    created_at TEXT NOT NULL
  );

  CREATE INDEX IF NOT EXISTS attachments_record_id
    ON attachments (record_id);

  PRAGMA user_version = 1;
`;

export async function migrateDatabase(database: SQLiteDatabase): Promise<void> {
  await database.execAsync('PRAGMA foreign_keys = ON;');

  const versionRow = await database.getFirstAsync<{ user_version: number }>(
    'PRAGMA user_version;',
  );
  const currentVersion = versionRow?.user_version ?? 0;

  if (currentVersion > LATEST_DATABASE_VERSION) {
    throw new Error(
      `Database version ${currentVersion} is newer than supported version ${LATEST_DATABASE_VERSION}.`,
    );
  }

  if (currentVersion < 1) {
    let transactionStarted = false;
    try {
      await database.execAsync('BEGIN;');
      transactionStarted = true;
      await database.execAsync(VERSION_1_SCHEMA);
      await database.execAsync('COMMIT;');
      transactionStarted = false;
    } catch (error) {
      if (transactionStarted) {
        try {
          await database.execAsync('ROLLBACK;');
        } catch {
          // The original migration error is the actionable failure.
        }
      }
      throw error;
    }
  }
}
