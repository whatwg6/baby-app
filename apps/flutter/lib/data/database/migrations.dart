import 'package:sqflite/sqflite.dart';

const schemaVersion = 1;

Future<void> migrateDatabase(
  Database database,
  int oldVersion,
  int newVersion,
) async {
  if (oldVersion < 1 && newVersion >= 1) {
    await _createVersion1(database);
  }
}

Future<void> _createVersion1(Database database) async {
  await database.execute('''
    CREATE TABLE baby (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      birth_date TEXT NOT NULL,
      sex TEXT,
      avatar_path TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE records (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      occurred_at TEXT NOT NULL,
      note TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE INDEX records_occurred_at_desc_idx
    ON records(occurred_at DESC)
  ''');
  await database.execute('''
    CREATE TABLE growth_details (
      id TEXT PRIMARY KEY,
      record_id TEXT NOT NULL UNIQUE,
      height_cm REAL,
      weight_kg REAL,
      head_cm REAL,
      FOREIGN KEY(record_id) REFERENCES records(id) ON DELETE CASCADE
    )
  ''');
  await database.execute('''
    CREATE TABLE activity_details (
      id TEXT PRIMARY KEY,
      record_id TEXT NOT NULL UNIQUE,
      activity_type TEXT NOT NULL,
      amount REAL,
      duration_minutes INTEGER,
      FOREIGN KEY(record_id) REFERENCES records(id) ON DELETE CASCADE
    )
  ''');
  await database.execute('''
    CREATE TABLE milestone_details (
      id TEXT PRIMARY KEY,
      record_id TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL,
      preset_key TEXT,
      FOREIGN KEY(record_id) REFERENCES records(id) ON DELETE CASCADE
    )
  ''');
  await database.execute('''
    CREATE TABLE attachments (
      id TEXT PRIMARY KEY,
      record_id TEXT NOT NULL,
      media_type TEXT NOT NULL,
      file_path TEXT NOT NULL,
      thumbnail_path TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(record_id) REFERENCES records(id) ON DELETE CASCADE
    )
  ''');
  await database.execute('''
    CREATE INDEX attachments_record_id_idx ON attachments(record_id)
  ''');
}
