import type {
  Attachment,
  Baby,
  BabyInput,
  NewRecordInput,
  RecordType,
  TimelineRecord,
} from '../domain/types';
import type {
  BabyRepository,
  RecordListOptions,
  RecordPage,
  RecordPageCursor,
  RecordRepository,
  RecordTransaction,
} from '../data/repositories';

export class MemoryBabyRepository implements BabyRepository {
  private baby: Baby | null = null;

  async get(): Promise<Baby | null> {
    return this.baby === null ? null : copy(this.baby);
  }

  async save(input: BabyInput): Promise<Baby> {
    const now = new Date().toISOString();
    this.baby = {
      id: this.baby?.id ?? createId(),
      ...input,
      createdAt: this.baby?.createdAt ?? now,
      updatedAt: now,
    };
    return copy(this.baby);
  }

  async clear(): Promise<void> {
    this.baby = null;
  }
}

class MemoryRecordTransaction implements RecordTransaction {
  constructor(private readonly records: Map<string, TimelineRecord>) {}

  async create(input: NewRecordInput): Promise<TimelineRecord> {
    const now = new Date().toISOString();
    const id = createId();
    const record: TimelineRecord = {
      id,
      type: input.type,
      occurredAt: input.occurredAt,
      note: input.note,
      details: copy(input.details),
      attachments: input.attachments.map((attachment) => ({
        id: attachment.id ?? createId(),
        recordId: id,
        mediaType: attachment.mediaType,
        filePath: attachment.filePath,
        thumbnailPath: attachment.thumbnailPath,
        createdAt: now,
      })),
      createdAt: now,
      updatedAt: now,
    };
    this.records.set(id, record);
    return copy(record);
  }

  async update(id: string, input: NewRecordInput): Promise<TimelineRecord> {
    const existing = this.records.get(id);
    if (existing === undefined) {
      throw new Error(`Record ${id} was not found.`);
    }

    const now = new Date().toISOString();
    const previousAttachments = new Map(
      existing.attachments.map((attachment) => [attachment.id, attachment]),
    );
    const updated: TimelineRecord = {
      id,
      type: input.type,
      occurredAt: input.occurredAt,
      note: input.note,
      details: copy(input.details),
      attachments: input.attachments.map((attachment) => ({
        id: attachment.id ?? createId(),
        recordId: id,
        mediaType: attachment.mediaType,
        filePath: attachment.filePath,
        thumbnailPath: attachment.thumbnailPath,
        createdAt: attachment.id === undefined
          ? now
          : previousAttachments.get(attachment.id)?.createdAt ?? now,
      })),
      createdAt: existing.createdAt,
      updatedAt: now,
    };
    this.records.set(id, updated);
    return copy(updated);
  }

  async delete(id: string): Promise<Attachment[]> {
    const existing = this.records.get(id);
    if (existing === undefined) {
      throw new Error(`Record ${id} was not found.`);
    }
    this.records.delete(id);
    return copy(existing.attachments);
  }
}

export class MemoryRecordRepository implements RecordRepository {
  private records = new Map<string, TimelineRecord>();

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
    const types = filter?.types;
    return this.sortedRecords(types)
      .map(copy);
  }

  async listPage(options: RecordListOptions = {}): Promise<RecordPage> {
    const limit = normalizePageLimit(options.limit);
    const cursor = options.cursor ?? null;
    const candidates = this.sortedRecords(options.types)
      .filter((record) => cursor === null || isAfterCursor(record, cursor));
    const records = candidates.slice(0, limit);
    const lastRecord = records.at(-1);

    return {
      records: records.map(copy),
      nextCursor: candidates.length > limit && lastRecord !== undefined
        ? toCursor(lastRecord)
        : null,
    };
  }

  private sortedRecords(types?: RecordType[]): TimelineRecord[] {
    return [...this.records.values()]
      .filter((record) => types === undefined || types.length === 0 || types.includes(record.type))
      .sort(compareRecordsDescending);
  }

  async get(id: string): Promise<TimelineRecord | null> {
    const record = this.records.get(id);
    return record === undefined ? null : copy(record);
  }

  async withTransaction<T>(
    work: (transaction: RecordTransaction) => Promise<T>,
  ): Promise<T> {
    const stagedRecords = new Map(
      [...this.records.entries()].map(([id, record]) => [id, copy(record)]),
    );
    const value = await work(new MemoryRecordTransaction(stagedRecords));
    this.records = stagedRecords;
    return value;
  }
}

function normalizePageLimit(limit: number | undefined): number {
  if (limit === undefined || !Number.isFinite(limit)) {
    return 20;
  }
  return Math.max(1, Math.min(100, Math.trunc(limit)));
}

function compareRecordsDescending(left: TimelineRecord, right: TimelineRecord): number {
  return right.occurredAt.localeCompare(left.occurredAt)
    || right.createdAt.localeCompare(left.createdAt)
    || right.id.localeCompare(left.id);
}

function isAfterCursor(record: TimelineRecord, cursor: RecordPageCursor): boolean {
  return record.occurredAt < cursor.occurredAt
    || (record.occurredAt === cursor.occurredAt && record.createdAt < cursor.createdAt)
    || (
      record.occurredAt === cursor.occurredAt
      && record.createdAt === cursor.createdAt
      && record.id < cursor.id
    );
}

function toCursor(record: TimelineRecord): RecordPageCursor {
  return {
    occurredAt: record.occurredAt,
    createdAt: record.createdAt,
    id: record.id,
  };
}

let nextId = 0;

function createId(): string {
  nextId += 1;
  return `memory-${nextId}`;
}

function copy<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}
