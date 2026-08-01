import type {
  Attachment,
  Baby,
  BabyInput,
  NewRecordInput,
  RecordType,
  TimelineRecord,
} from '../domain/types';
import type { BabyRepository, RecordRepository, RecordTransaction } from '../data/repositories';

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
    return [...this.records.values()]
      .filter((record) => types === undefined || types.length === 0 || types.includes(record.type))
      .sort((left, right) => right.occurredAt.localeCompare(left.occurredAt))
      .map(copy);
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

let nextId = 0;

function createId(): string {
  nextId += 1;
  return `memory-${nextId}`;
}

function copy<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}
