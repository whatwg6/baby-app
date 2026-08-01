import type { SQLiteDatabase } from 'expo-sqlite';

import type {
  ActivityDetails,
  Attachment,
  Baby,
  GrowthDetails,
  MilestoneDetails,
  RecordType,
} from '../../domain/types';
import {
  createSQLiteRepositories,
  type RecordRepository,
} from '../repositories';
import { MemoryRecordRepository } from '../../test/memoryRepositories';
import {
  babyInputFixture,
  momentInputFixture,
  recordVariantFixtures,
} from '../../test/fixtures';

type RecordRow = {
  id: string;
  type: RecordType;
  occurred_at: string;
  note: string | null;
  created_at: string;
  updated_at: string;
};

type AttachmentRow = {
  id: string;
  record_id: string;
  media_type: 'image' | 'video';
  file_path: string;
  thumbnail_path: string | null;
  created_at: string;
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

class SQLiteRepositoryDouble {
  readonly databasePath = ':memory:';
  private records = new Map<string, RecordRow>();
  private growthDetails = new Map<string, GrowthDetails>();
  private activityDetails = new Map<string, ActivityDetails>();
  private milestoneDetails = new Map<string, MilestoneDetails>();
  private attachments = new Map<string, AttachmentRow>();
  private babies: BabyRow[] = [];
  private transactionActive = false;

  get babyRowCount(): number {
    return this.babies.length;
  }

  async withExclusiveTransactionAsync(
    work: (transaction: SQLiteDatabase) => Promise<void>,
  ): Promise<void> {
    if (this.transactionActive) {
      throw new Error('Nested transaction');
    }

    const snapshot = this.snapshot();
    this.transactionActive = true;
    try {
      await work(this as unknown as SQLiteDatabase);
    } catch (error) {
      this.restore(snapshot);
      throw error;
    } finally {
      this.transactionActive = false;
    }
  }

  async runAsync(sql: string, ...rawParams: unknown[]): Promise<{ changes: number }> {
    const params = bindParams(rawParams);

    if (sql.includes('INSERT INTO baby')) {
      const [id, name, birthDate, sex, avatarPath, createdAt, updatedAt] = params as [
        string,
        string,
        string,
        Baby['sex'],
        string | null,
        string,
        string,
      ];
      if (sql.includes('ON CONFLICT(singleton)') && this.babies[0] !== undefined) {
        this.babies[0] = {
          ...this.babies[0],
          name,
          birth_date: birthDate,
          sex,
          avatar_path: avatarPath,
          updated_at: updatedAt,
        };
      } else {
        this.babies.push({
          id,
          name,
          birth_date: birthDate,
          sex,
          avatar_path: avatarPath,
          created_at: createdAt,
          updated_at: updatedAt,
        });
      }
      return { changes: 1 };
    }

    if (sql.includes('UPDATE baby')) {
      const [name, birthDate, sex, avatarPath, updatedAt, id] = params as [
        string,
        string,
        Baby['sex'],
        string | null,
        string,
        string,
      ];
      const index = this.babies.findIndex((baby) => baby.id === id);
      if (index === -1) {
        return { changes: 0 };
      }
      this.babies[index] = {
        ...this.babies[index],
        name,
        birth_date: birthDate,
        sex,
        avatar_path: avatarPath,
        updated_at: updatedAt,
      };
      return { changes: 1 };
    }

    if (sql.includes('DELETE FROM baby')) {
      const changes = this.babies.length;
      this.babies = [];
      return { changes };
    }

    if (sql.includes('INSERT INTO records')) {
      const [id, type, occurredAt, note, createdAt, updatedAt] = params as string[];
      this.records.set(id, {
        id,
        type: type as RecordType,
        occurred_at: occurredAt,
        note: note ?? null,
        created_at: createdAt,
        updated_at: updatedAt,
      });
      return { changes: 1 };
    }

    if (sql.includes('UPDATE records')) {
      const [type, occurredAt, note, updatedAt, id] = params as string[];
      const record = this.records.get(id);
      if (record === undefined) {
        return { changes: 0 };
      }
      this.records.set(id, {
        ...record,
        type: type as RecordType,
        occurred_at: occurredAt,
        note: note ?? null,
        updated_at: updatedAt,
      });
      return { changes: 1 };
    }

    if (sql.includes('INSERT INTO growth_details')) {
      const [recordId, heightCm, weightKg, headCm] = params as [string, number | null, number | null, number | null];
      this.growthDetails.set(recordId, { heightCm, weightKg, headCm });
      return { changes: 1 };
    }

    if (sql.includes('INSERT INTO activity_details')) {
      const [recordId, activityType, amount, durationMinutes] = params as [
        string,
        ActivityDetails['activityType'],
        number | null,
        number | null,
      ];
      this.activityDetails.set(recordId, { activityType, amount, durationMinutes });
      return { changes: 1 };
    }

    if (sql.includes('INSERT INTO milestone_details')) {
      const [recordId, title, presetKey] = params as [string, string, string | null];
      this.milestoneDetails.set(recordId, { title, presetKey });
      return { changes: 1 };
    }

    if (sql.includes('INSERT INTO attachments')) {
      const [id, recordId, mediaType, filePath, thumbnailPath, createdAt] = params as [
        string,
        string,
        'image' | 'video',
        string,
        string | null,
        string,
      ];
      this.attachments.set(id, {
        id,
        record_id: recordId,
        media_type: mediaType,
        file_path: filePath,
        thumbnail_path: thumbnailPath,
        created_at: createdAt,
      });
      return { changes: 1 };
    }

    if (sql.includes('UPDATE attachments')) {
      const [mediaType, filePath, thumbnailPath, id, recordId] = params as [
        'image' | 'video',
        string,
        string | null,
        string,
        string,
      ];
      const attachment = this.attachments.get(id);
      if (attachment === undefined || attachment.record_id !== recordId) {
        return { changes: 0 };
      }
      this.attachments.set(id, {
        ...attachment,
        media_type: mediaType,
        file_path: filePath,
        thumbnail_path: thumbnailPath,
      });
      return { changes: 1 };
    }

    if (sql.includes('DELETE FROM growth_details')) {
      this.growthDetails.delete(params[0] as string);
      return { changes: 1 };
    }
    if (sql.includes('DELETE FROM activity_details')) {
      this.activityDetails.delete(params[0] as string);
      return { changes: 1 };
    }
    if (sql.includes('DELETE FROM milestone_details')) {
      this.milestoneDetails.delete(params[0] as string);
      return { changes: 1 };
    }
    if (sql.includes('DELETE FROM attachments WHERE id = ? AND record_id = ?')) {
      const [id, recordId] = params as [string, string];
      const attachment = this.attachments.get(id);
      if (attachment === undefined || attachment.record_id !== recordId) {
        return { changes: 0 };
      }
      this.attachments.delete(id);
      return { changes: 1 };
    }
    if (sql.includes('DELETE FROM attachments WHERE record_id')) {
      for (const attachment of this.attachments.values()) {
        if (attachment.record_id === params[0]) {
          this.attachments.delete(attachment.id);
        }
      }
      return { changes: 1 };
    }
    if (sql.includes('DELETE FROM records')) {
      const id = params[0] as string;
      const deleted = this.records.delete(id);
      this.growthDetails.delete(id);
      this.activityDetails.delete(id);
      this.milestoneDetails.delete(id);
      for (const attachment of this.attachments.values()) {
        if (attachment.record_id === id) {
          this.attachments.delete(attachment.id);
        }
      }
      return { changes: deleted ? 1 : 0 };
    }

    throw new Error(`Unhandled SQL: ${sql}`);
  }

  async getFirstAsync<T>(sql: string, ...rawParams: unknown[]): Promise<T | null> {
    const params = bindParams(rawParams);
    const recordId = params[0] as string;

    if (sql.includes('FROM baby')) {
      return (this.babies[0] ?? null) as T | null;
    }
    if (sql.includes('FROM records')) {
      return (this.records.get(recordId) ?? null) as T | null;
    }
    if (sql.includes('FROM growth_details')) {
      return (this.growthDetails.get(recordId) ?? null) as T | null;
    }
    if (sql.includes('FROM activity_details')) {
      return (this.activityDetails.get(recordId) ?? null) as T | null;
    }
    if (sql.includes('FROM milestone_details')) {
      return (this.milestoneDetails.get(recordId) ?? null) as T | null;
    }

    throw new Error(`Unhandled SQL: ${sql}`);
  }

  async getAllAsync<T>(sql: string, ...rawParams: unknown[]): Promise<T[]> {
    const params = bindParams(rawParams);
    if (sql.includes('FROM records')) {
      const requestedTypes = params as RecordType[];
      return [...this.records.values()]
        .filter((record) => requestedTypes.length === 0 || requestedTypes.includes(record.type))
        .sort((left, right) => right.occurred_at.localeCompare(left.occurred_at)) as T[];
    }
    if (sql.includes('FROM attachments')) {
      const recordId = params[0] as string;
      return [...this.attachments.values()]
        .filter((attachment) => attachment.record_id === recordId)
        .sort((left, right) => left.created_at.localeCompare(right.created_at)) as T[];
    }

    throw new Error(`Unhandled SQL: ${sql}`);
  }

  private snapshot() {
    return {
      records: new Map(this.records),
      growthDetails: new Map(this.growthDetails),
      activityDetails: new Map(this.activityDetails),
      milestoneDetails: new Map(this.milestoneDetails),
      attachments: new Map(this.attachments),
    };
  }

  private restore(snapshot: ReturnType<SQLiteRepositoryDouble['snapshot']>): void {
    this.records = snapshot.records;
    this.growthDetails = snapshot.growthDetails;
    this.activityDetails = snapshot.activityDetails;
    this.milestoneDetails = snapshot.milestoneDetails;
    this.attachments = snapshot.attachments;
  }
}

function bindParams(rawParams: unknown[]): unknown[] {
  return Array.isArray(rawParams[0]) ? rawParams[0] as unknown[] : rawParams;
}

export function recordRepositoryContract(
  createRepository: () => Promise<RecordRepository>,
): void {
  test('creates, lists, updates and deletes a complete record', async () => {
    const repository = await createRepository();
    const created = await repository.create(momentInputFixture());

    expect(created).toMatchObject({
      type: 'moment',
      note: '第一次看向镜头',
      details: null,
      attachments: [
        {
          id: 'attachment-image-1',
          mediaType: 'image',
          filePath: 'file:///media/first-look.jpg',
          thumbnailPath: 'file:///media/first-look-thumb.jpg',
        },
      ],
    });
    expect((await repository.list()).map((record) => record.id)).toEqual([created.id]);

    const updated = await repository.update(created.id, {
      ...momentInputFixture(),
      note: '修改后',
    });
    expect(updated.note).toBe('修改后');
    expect((await repository.get(created.id))?.note).toBe('修改后');

    const attachments = await repository.delete(created.id);
    expect(attachments).toMatchObject([{ id: 'attachment-image-1' }]);
    expect(await repository.get(created.id)).toBeNull();
  });

  test('round trips every record variant and filters complete timeline records', async () => {
    const repository = await createRepository();
    const records = [];
    for (const input of recordVariantFixtures()) {
      records.push(await repository.create(input));
    }

    expect((await repository.list({ types: ['growth', 'milestone'] })).map((record) => record.type)).toEqual([
      'milestone',
      'growth',
    ]);
    expect(await repository.get(records[1].id)).toMatchObject({
      details: { heightCm: 66.2, weightKg: 7.4, headCm: null },
    });
    expect(await repository.get(records[2].id)).toMatchObject({
      details: { activityType: 'sleep', amount: null, durationMinutes: 45 },
    });
    expect(await repository.get(records[3].id)).toMatchObject({
      details: { title: '会翻身', presetKey: 'roll-over' },
    });
  });

  test('treats an empty type selection as an unfiltered timeline', async () => {
    const repository = await createRepository();
    const created = await repository.create(momentInputFixture());

    expect((await repository.list({ types: [] })).map((record) => record.id)).toEqual([
      created.id,
    ]);
  });

  test('keeps an existing attachment index timestamp when updating its record', async () => {
    jest.useFakeTimers();
    try {
      jest.setSystemTime(new Date('2026-08-01T09:30:00.000Z'));
      const repository = await createRepository();
      const created = await repository.create(momentInputFixture());
      jest.setSystemTime(new Date('2026-08-02T09:30:00.000Z'));

      const updated = await repository.update(created.id, {
        ...momentInputFixture(),
        note: '保留媒体索引',
      });

      expect(updated.attachments[0].createdAt).toBe(created.attachments[0].createdAt);
    } finally {
      jest.useRealTimers();
    }
  });

  test('rolls back record writes when transaction work throws', async () => {
    const repository = await createRepository();

    await expect(
      repository.withTransaction(async (transaction) => {
        await transaction.create(momentInputFixture());
        throw new Error('cancel record save');
      }),
    ).rejects.toThrow('cancel record save');

    expect(await repository.list()).toEqual([]);
  });
}

describe('MemoryRecordRepository', () => {
  recordRepositoryContract(async () => new MemoryRecordRepository());
});

describe('SQLite RecordRepository mapping', () => {
  recordRepositoryContract(async () => {
    const database = new SQLiteRepositoryDouble();
    return createSQLiteRepositories(database as unknown as SQLiteDatabase).records;
  });
});

describe('SQLite BabyRepository mapping', () => {
  test('concurrent first saves retain exactly one baby profile', async () => {
    const database = new SQLiteRepositoryDouble();
    const babies = createSQLiteRepositories(database as unknown as SQLiteDatabase).babies;

    await Promise.all([
      babies.save(babyInputFixture()),
      babies.save({ ...babyInputFixture(), name: '乐乐' }),
    ]);

    expect(database.babyRowCount).toBe(1);
  });
});
