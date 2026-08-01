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

export interface RecordPageCursor {
  occurredAt: string;
  createdAt: string;
  id: string;
}

export interface RecordListOptions {
  types?: RecordType[];
  cursor?: RecordPageCursor | null;
  limit?: number;
}

export interface RecordPage {
  records: TimelineRecord[];
  nextCursor: RecordPageCursor | null;
}

export interface RecordRepository extends RecordTransaction {
  list(filter?: { types?: RecordType[] }): Promise<TimelineRecord[]>;
  listPage(options?: RecordListOptions): Promise<RecordPage>;
  get(id: string): Promise<TimelineRecord | null>;
  withTransaction<T>(work: (transaction: RecordTransaction) => Promise<T>): Promise<T>;
}

export interface MediaReferenceRepository {
  listReferencedMediaPaths(): Promise<string[]>;
}

export interface SQLiteRepositories {
  babies: BabyRepository;
  records: RecordRepository;
  mediaReferences: MediaReferenceRepository;
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

type GrowthDetailsRow = GrowthDetails & { recordId: string };
type ActivityDetailsRow = ActivityDetails & { recordId: string };
type MilestoneDetailsRow = MilestoneDetails & { recordId: string };

class SQLiteBabyRepository implements BabyRepository {
  constructor(private readonly database: SQLiteDatabase) {}

  async get(): Promise<Baby | null> {
    return getBaby(this.database);
  }

  async save(input: BabyInput): Promise<Baby> {
    const now = new Date().toISOString();
    let saved: Baby | null = null;
    await this.database.withExclusiveTransactionAsync(async (database) => {
      await database.runAsync(
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
      saved = await getBaby(database);
      if (saved === null) {
        throw new Error('Baby profile was not saved.');
      }
    });
    if (saved === null) {
      throw new Error('Baby profile was not saved.');
    }
    return saved;
  }

  async clear(): Promise<void> {
    await this.database.runAsync('DELETE FROM baby;');
  }
}

async function getBaby(database: SQLiteDatabase): Promise<Baby | null> {
  const row = await database.getFirstAsync<BabyRow>(`
    SELECT id, name, birth_date, sex, avatar_path, created_at, updated_at
    FROM baby
    WHERE singleton = 1;
  `);
  return row === null ? null : toBaby(row);
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
        ORDER BY occurred_at DESC, created_at DESC, id DESC;
      `);
      return hydrateRecords(this.database, rows);
    }

    const placeholders = types.map(() => '?').join(', ');
    const rows = await this.database.getAllAsync<RecordRow>(`
      SELECT id, type, occurred_at, note, created_at, updated_at
      FROM records
      WHERE type IN (${placeholders})
      ORDER BY occurred_at DESC, created_at DESC, id DESC;
    `, types);
    return hydrateRecords(this.database, rows);
  }

  async listPage(options: RecordListOptions = {}): Promise<RecordPage> {
    const types = options.types ?? [];
    const cursor = options.cursor ?? null;
    const limit = normalizePageLimit(options.limit);
    const clauses: string[] = [];
    const parameters: Array<string | number> = [];

    if (types.length > 0) {
      clauses.push(`type IN (${types.map(() => '?').join(', ')})`);
      parameters.push(...types);
    }
    if (cursor !== null) {
      clauses.push(`(
        occurred_at < ?
        OR (occurred_at = ? AND created_at < ?)
        OR (occurred_at = ? AND created_at = ? AND id < ?)
      )`);
      parameters.push(
        cursor.occurredAt,
        cursor.occurredAt,
        cursor.createdAt,
        cursor.occurredAt,
        cursor.createdAt,
        cursor.id,
      );
    }

    const where = clauses.length === 0 ? '' : `WHERE ${clauses.join(' AND ')}`;
    const rows = await this.database.getAllAsync<RecordRow>(`
      SELECT id, type, occurred_at, note, created_at, updated_at
      FROM records
      ${where}
      ORDER BY occurred_at DESC, created_at DESC, id DESC
      LIMIT ?;
    `, [...parameters, limit + 1]);
    const pageRows = rows.slice(0, limit);
    const records = await hydrateRecords(this.database, pageRows);
    const lastRow = pageRows.at(-1);

    return {
      records,
      nextCursor: rows.length > limit && lastRow !== undefined
        ? toRecordPageCursor(lastRow)
        : null,
    };
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

class SQLiteMediaReferenceRepository implements MediaReferenceRepository {
  constructor(private readonly database: SQLiteDatabase) {}

  async listReferencedMediaPaths(): Promise<string[]> {
    const rows = await this.database.getAllAsync<{ path: string }>(`
      SELECT avatar_path AS path FROM baby WHERE avatar_path IS NOT NULL
      UNION ALL
      SELECT file_path AS path FROM attachments
      UNION ALL
      SELECT thumbnail_path AS path FROM attachments WHERE thumbnail_path IS NOT NULL;
    `);
    return [...new Set(rows.map((row) => row.path))];
  }
}

function normalizePageLimit(limit: number | undefined): number {
  if (limit === undefined || !Number.isFinite(limit)) {
    return 20;
  }
  return Math.max(1, Math.min(100, Math.trunc(limit)));
}

function toRecordPageCursor(row: RecordRow): RecordPageCursor {
  return {
    occurredAt: row.occurred_at,
    createdAt: row.created_at,
    id: row.id,
  };
}

async function hydrateRecords(
  database: SQLiteDatabase,
  rows: RecordRow[],
): Promise<TimelineRecord[]> {
  if (rows.length === 0) {
    return [];
  }

  const growthIds = rows.filter((row) => row.type === 'growth').map((row) => row.id);
  const activityIds = rows.filter((row) => row.type === 'activity').map((row) => row.id);
  const milestoneIds = rows.filter((row) => row.type === 'milestone').map((row) => row.id);
  const recordIds = rows.map((row) => row.id);
  const [growthRows, activityRows, milestoneRows, attachmentRows] = await Promise.all([
    listGrowthDetails(database, growthIds),
    listActivityDetails(database, activityIds),
    listMilestoneDetails(database, milestoneIds),
    listAttachmentsForRecords(database, recordIds),
  ]);
  const growthByRecord = new Map(growthRows.map((details) => [details.recordId, details]));
  const activityByRecord = new Map(activityRows.map((details) => [details.recordId, details]));
  const milestoneByRecord = new Map(milestoneRows.map((details) => [details.recordId, details]));
  const attachmentsByRecord = new Map<string, Attachment[]>();
  for (const attachmentRow of attachmentRows) {
    const attachments = attachmentsByRecord.get(attachmentRow.record_id) ?? [];
    attachments.push(toAttachment(attachmentRow));
    attachmentsByRecord.set(attachmentRow.record_id, attachments);
  }

  return rows.map((row) => ({
    id: row.id,
    type: row.type,
    occurredAt: row.occurred_at,
    note: row.note,
    details: batchDetails(row, growthByRecord, activityByRecord, milestoneByRecord),
    attachments: attachmentsByRecord.get(row.id) ?? [],
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }));
}

async function listGrowthDetails(
  database: SQLiteDatabase,
  recordIds: string[],
): Promise<GrowthDetailsRow[]> {
  if (recordIds.length === 0) {
    return [];
  }
  return database.getAllAsync<GrowthDetailsRow>(`
    SELECT record_id AS recordId,
           height_cm AS heightCm,
           weight_kg AS weightKg,
           head_cm AS headCm
    FROM growth_details
    WHERE record_id IN (${recordIds.map(() => '?').join(', ')});
  `, recordIds);
}

async function listActivityDetails(
  database: SQLiteDatabase,
  recordIds: string[],
): Promise<ActivityDetailsRow[]> {
  if (recordIds.length === 0) {
    return [];
  }
  return database.getAllAsync<ActivityDetailsRow>(`
    SELECT record_id AS recordId,
           activity_type AS activityType,
           amount,
           duration_minutes AS durationMinutes
    FROM activity_details
    WHERE record_id IN (${recordIds.map(() => '?').join(', ')});
  `, recordIds);
}

async function listMilestoneDetails(
  database: SQLiteDatabase,
  recordIds: string[],
): Promise<MilestoneDetailsRow[]> {
  if (recordIds.length === 0) {
    return [];
  }
  return database.getAllAsync<MilestoneDetailsRow>(`
    SELECT record_id AS recordId, title, preset_key AS presetKey
    FROM milestone_details
    WHERE record_id IN (${recordIds.map(() => '?').join(', ')});
  `, recordIds);
}

async function listAttachmentsForRecords(
  database: SQLiteDatabase,
  recordIds: string[],
): Promise<AttachmentRow[]> {
  return database.getAllAsync<AttachmentRow>(`
    SELECT id, record_id, media_type, file_path, thumbnail_path, created_at
    FROM attachments
    WHERE record_id IN (${recordIds.map(() => '?').join(', ')})
    ORDER BY record_id ASC, created_at ASC, id ASC;
  `, recordIds);
}

function batchDetails(
  row: RecordRow,
  growthByRecord: Map<string, GrowthDetailsRow>,
  activityByRecord: Map<string, ActivityDetailsRow>,
  milestoneByRecord: Map<string, MilestoneDetailsRow>,
): TimelineRecord['details'] {
  switch (row.type) {
    case 'moment':
      return null;
    case 'growth': {
      const details = growthByRecord.get(row.id);
      if (details === undefined) {
        throw new Error(`Growth record ${row.id} has no details.`);
      }
      const { recordId: _recordId, ...value } = details;
      return value;
    }
    case 'activity': {
      const details = activityByRecord.get(row.id);
      if (details === undefined) {
        throw new Error(`Activity record ${row.id} has no details.`);
      }
      const { recordId: _recordId, ...value } = details;
      return value;
    }
    case 'milestone': {
      const details = milestoneByRecord.get(row.id);
      if (details === undefined) {
        throw new Error(`Milestone record ${row.id} has no details.`);
      }
      const { recordId: _recordId, ...value } = details;
      return value;
    }
  }
}

export function createSQLiteRepositories(database: SQLiteDatabase): SQLiteRepositories {
  return {
    babies: new SQLiteBabyRepository(database),
    records: new SQLiteRecordRepository(database),
    mediaReferences: new SQLiteMediaReferenceRepository(database),
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
