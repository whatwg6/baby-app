import type { SQLiteDatabase } from 'expo-sqlite';

import type {
  ActivityDetails,
  Attachment,
  Baby,
  BabyInput,
  GrowthDetails,
  MilestoneDetails,
  NewAttachmentInput,
  NewRecordInput,
  RecordType,
  TimelineRecord,
} from '../domain/types';

export interface BabyRepository {
  get(): Promise<Baby | null>;
  save(input: BabyInput): Promise<Baby>;
  clear(): Promise<void>;
}

export interface RecordTransaction {
  create(input: NewRecordInput): Promise<TimelineRecord>;
  update(id: string, input: NewRecordInput): Promise<TimelineRecord>;
  delete(id: string): Promise<Attachment[]>;
}

export interface RecordRepository extends RecordTransaction {
  list(filter?: { types?: RecordType[] }): Promise<TimelineRecord[]>;
  get(id: string): Promise<TimelineRecord | null>;
  withTransaction<T>(work: (transaction: RecordTransaction) => Promise<T>): Promise<T>;
}

export interface SQLiteRepositories {
  babies: BabyRepository;
  records: RecordRepository;
}

type RecordRow = {
  id: string;
  type: RecordType;
  occurred_at: string;
  note: string | null;
  created_at: string;
  updated_at: string;
};

type BabyRow = {
  id: string;
  name: string;
  birth_date: string;
  sex: Baby['sex'];
  avatar_path: string | null;
  created_at: string;
  updated_at: string;
};

type AttachmentRow = {
  id: string;
  record_id: string;
  media_type: Attachment['mediaType'];
  file_path: string;
  thumbnail_path: string | null;
  created_at: string;
};

class SQLiteBabyRepository implements BabyRepository {
  constructor(private readonly database: SQLiteDatabase) {}

  async get(): Promise<Baby | null> {
    const row = await this.database.getFirstAsync<BabyRow>(`
      SELECT id, name, birth_date, sex, avatar_path, created_at, updated_at
      FROM baby
      WHERE singleton = 1;
    `);

    return row === null ? null : toBaby(row);
  }

  async save(input: BabyInput): Promise<Baby> {
    const now = new Date().toISOString();
    await this.database.runAsync(
      `INSERT INTO baby (
        singleton, id, name, birth_date, sex, avatar_path, created_at, updated_at
      ) VALUES (1, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(singleton) DO UPDATE SET
        name = excluded.name,
        birth_date = excluded.birth_date,
        sex = excluded.sex,
        avatar_path = excluded.avatar_path,
        updated_at = excluded.updated_at;`,
      [
        createId(),
        input.name,
        input.birthDate,
        input.sex,
        input.avatarPath,
        now,
        now,
      ],
    );
    const saved = await this.get();
    if (saved === null) {
      throw new Error('Baby profile was not saved.');
    }
    return saved;
  }

  async clear(): Promise<void> {
    await this.database.runAsync('DELETE FROM baby;');
  }
}

class SQLiteRecordTransaction implements RecordTransaction {
  constructor(private readonly database: SQLiteDatabase) {}

  async create(input: NewRecordInput): Promise<TimelineRecord> {
    const id = createId();
    const now = new Date().toISOString();
    await this.database.runAsync(
      `INSERT INTO records (
        id, type, occurred_at, note, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?);`,
      [id, input.type, input.occurredAt, input.note, now, now],
    );
    await writeDetails(this.database, id, input);
    await writeAttachments(this.database, id, input.attachments, now);

    return requireRecord(this.database, id);
  }

  async update(id: string, input: NewRecordInput): Promise<TimelineRecord> {
    const now = new Date().toISOString();
    const result = await this.database.runAsync(
      `UPDATE records
       SET type = ?, occurred_at = ?, note = ?, updated_at = ?
       WHERE id = ?;`,
      [input.type, input.occurredAt, input.note, now, id],
    );
    if (result.changes === 0) {
      throw new Error(`Record ${id} was not found.`);
    }

    const existingAttachments = await listAttachments(this.database, id);
    await clearDetails(this.database, id);
    await writeDetails(this.database, id, input);
    await syncAttachments(
      this.database,
      id,
      input.attachments,
      existingAttachments,
      now,
    );

    return requireRecord(this.database, id);
  }

  async delete(id: string): Promise<Attachment[]> {
    const attachments = await listAttachments(this.database, id);
    const result = await this.database.runAsync('DELETE FROM records WHERE id = ?;', [id]);
    if (result.changes === 0) {
      throw new Error(`Record ${id} was not found.`);
    }
    return attachments;
  }
}

class SQLiteRecordRepository implements RecordRepository {
  constructor(private readonly database: SQLiteDatabase) {}

  async create(input: NewRecordInput): Promise<TimelineRecord> {
    return this.withTransaction((transaction) => transaction.create(input));
  }

  async update(id: string, input: NewRecordInput): Promise<TimelineRecord> {
    return this.withTransaction((transaction) => transaction.update(id, input));
  }

  async delete(id: string): Promise<Attachment[]> {
    return this.withTransaction((transaction) => transaction.delete(id));
  }

  async list(filter?: { types?: RecordType[] }): Promise<TimelineRecord[]> {
    const types = filter?.types ?? [];
    if (types.length === 0) {
      const rows = await this.database.getAllAsync<RecordRow>(`
        SELECT id, type, occurred_at, note, created_at, updated_at
        FROM records
        ORDER BY occurred_at DESC, created_at DESC;
      `);
      return Promise.all(rows.map((row) => requireRecord(this.database, row.id)));
    }

    const placeholders = types.map(() => '?').join(', ');
    const rows = await this.database.getAllAsync<RecordRow>(`
      SELECT id, type, occurred_at, note, created_at, updated_at
      FROM records
      WHERE type IN (${placeholders})
      ORDER BY occurred_at DESC, created_at DESC;
    `, types);
    return Promise.all(rows.map((row) => requireRecord(this.database, row.id)));
  }

  get(id: string): Promise<TimelineRecord | null> {
    return getRecord(this.database, id);
  }

  async withTransaction<T>(
    work: (transaction: RecordTransaction) => Promise<T>,
  ): Promise<T> {
    let value: T | undefined;
    await this.database.withExclusiveTransactionAsync(async (database) => {
      const transaction = new SQLiteRecordTransaction(database);
      value = await work(transaction);
    });
    return value as T;
  }
}

export function createSQLiteRepositories(database: SQLiteDatabase): SQLiteRepositories {
  return {
    babies: new SQLiteBabyRepository(database),
    records: new SQLiteRecordRepository(database),
  };
}

async function getRecord(
  database: SQLiteDatabase,
  id: string,
): Promise<TimelineRecord | null> {
  const row = await database.getFirstAsync<RecordRow>(`
    SELECT id, type, occurred_at, note, created_at, updated_at
    FROM records
    WHERE id = ?;
  `, [id]);
  if (row === null) {
    return null;
  }

  return {
    id: row.id,
    type: row.type,
    occurredAt: row.occurred_at,
    note: row.note,
    details: await getDetails(database, row),
    attachments: await listAttachments(database, row.id),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function requireRecord(database: SQLiteDatabase, id: string): Promise<TimelineRecord> {
  const record = await getRecord(database, id);
  if (record === null) {
    throw new Error(`Record ${id} was not found.`);
  }
  return record;
}

async function getDetails(
  database: SQLiteDatabase,
  row: RecordRow,
): Promise<TimelineRecord['details']> {
  switch (row.type) {
    case 'moment':
      return null;
    case 'growth': {
      const details = await database.getFirstAsync<GrowthDetails>(`
        SELECT height_cm AS heightCm, weight_kg AS weightKg, head_cm AS headCm
        FROM growth_details
        WHERE record_id = ?;
      `, [row.id]);
      if (details === null) {
        throw new Error(`Growth record ${row.id} has no details.`);
      }
      return details;
    }
    case 'activity': {
      const details = await database.getFirstAsync<ActivityDetails>(`
        SELECT activity_type AS activityType, amount, duration_minutes AS durationMinutes
        FROM activity_details
        WHERE record_id = ?;
      `, [row.id]);
      if (details === null) {
        throw new Error(`Activity record ${row.id} has no details.`);
      }
      return details;
    }
    case 'milestone': {
      const details = await database.getFirstAsync<MilestoneDetails>(`
        SELECT title, preset_key AS presetKey
        FROM milestone_details
        WHERE record_id = ?;
      `, [row.id]);
      if (details === null) {
        throw new Error(`Milestone record ${row.id} has no details.`);
      }
      return details;
    }
  }
}

async function writeDetails(
  database: SQLiteDatabase,
  recordId: string,
  input: NewRecordInput,
): Promise<void> {
  switch (input.type) {
    case 'moment':
      return;
    case 'growth': {
      const details = input.details as GrowthDetails;
      await database.runAsync(
        `INSERT INTO growth_details (record_id, height_cm, weight_kg, head_cm)
         VALUES (?, ?, ?, ?);`,
        [recordId, details.heightCm, details.weightKg, details.headCm],
      );
      return;
    }
    case 'activity': {
      const details = input.details as ActivityDetails;
      await database.runAsync(
        `INSERT INTO activity_details (record_id, activity_type, amount, duration_minutes)
         VALUES (?, ?, ?, ?);`,
        [recordId, details.activityType, details.amount, details.durationMinutes],
      );
      return;
    }
    case 'milestone': {
      const details = input.details as MilestoneDetails;
      await database.runAsync(
        `INSERT INTO milestone_details (record_id, title, preset_key)
         VALUES (?, ?, ?);`,
        [recordId, details.title, details.presetKey],
      );
    }
  }
}

async function clearDetails(database: SQLiteDatabase, recordId: string): Promise<void> {
  await database.runAsync('DELETE FROM growth_details WHERE record_id = ?;', [recordId]);
  await database.runAsync('DELETE FROM activity_details WHERE record_id = ?;', [recordId]);
  await database.runAsync('DELETE FROM milestone_details WHERE record_id = ?;', [recordId]);
}

async function writeAttachments(
  database: SQLiteDatabase,
  recordId: string,
  attachments: NewAttachmentInput[],
  createdAt: string,
): Promise<void> {
  for (const attachment of attachments) {
    await database.runAsync(
      `INSERT INTO attachments (
        id, record_id, media_type, file_path, thumbnail_path, created_at
      ) VALUES (?, ?, ?, ?, ?, ?);`,
      [
        attachment.id ?? createId(),
        recordId,
        attachment.mediaType,
        attachment.filePath,
        attachment.thumbnailPath,
        createdAt,
      ],
    );
  }
}

async function syncAttachments(
  database: SQLiteDatabase,
  recordId: string,
  attachments: NewAttachmentInput[],
  existingAttachments: Attachment[],
  createdAt: string,
): Promise<void> {
  const existingById = new Map(
    existingAttachments.map((attachment) => [attachment.id, attachment]),
  );
  const desiredAttachments = attachments.map((attachment) => ({
    ...attachment,
    id: attachment.id ?? createId(),
  }));
  const desiredIds = new Set<string>();

  for (const attachment of desiredAttachments) {
    if (desiredIds.has(attachment.id)) {
      throw new Error(`Attachment ${attachment.id} is duplicated.`);
    }
    desiredIds.add(attachment.id);
  }

  for (const attachment of existingAttachments) {
    if (!desiredIds.has(attachment.id)) {
      await database.runAsync(
        'DELETE FROM attachments WHERE id = ? AND record_id = ?;',
        [attachment.id, recordId],
      );
    }
  }

  for (const attachment of desiredAttachments) {
    if (existingById.has(attachment.id)) {
      await database.runAsync(
        `UPDATE attachments
         SET media_type = ?, file_path = ?, thumbnail_path = ?
         WHERE id = ? AND record_id = ?;`,
        [
          attachment.mediaType,
          attachment.filePath,
          attachment.thumbnailPath,
          attachment.id,
          recordId,
        ],
      );
    } else {
      await database.runAsync(
        `INSERT INTO attachments (
          id, record_id, media_type, file_path, thumbnail_path, created_at
        ) VALUES (?, ?, ?, ?, ?, ?);`,
        [
          attachment.id,
          recordId,
          attachment.mediaType,
          attachment.filePath,
          attachment.thumbnailPath,
          createdAt,
        ],
      );
    }
  }
}

async function listAttachments(
  database: SQLiteDatabase,
  recordId: string,
): Promise<Attachment[]> {
  const rows = await database.getAllAsync<AttachmentRow>(`
    SELECT id, record_id, media_type, file_path, thumbnail_path, created_at
    FROM attachments
    WHERE record_id = ?
    ORDER BY created_at ASC, id ASC;
  `, [recordId]);
  return rows.map(toAttachment);
}

function toBaby(row: BabyRow): Baby {
  return {
    id: row.id,
    name: row.name,
    birthDate: row.birth_date,
    sex: row.sex,
    avatarPath: row.avatar_path,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function toAttachment(row: AttachmentRow): Attachment {
  return {
    id: row.id,
    recordId: row.record_id,
    mediaType: row.media_type,
    filePath: row.file_path,
    thumbnailPath: row.thumbnail_path,
    createdAt: row.created_at,
  };
}

let nextGeneratedId = 0;

function createId(): string {
  const crypto = globalThis.crypto;
  if (crypto !== undefined && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }

  nextGeneratedId += 1;
  return `local-${Date.now()}-${nextGeneratedId}-${Math.random().toString(36).slice(2)}`;
}
