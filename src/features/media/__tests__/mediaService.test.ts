import type {
  BabyRepository,
  RecordRepository,
  RecordTransaction,
} from '../../../data/repositories';
import type { NewRecordInput, RecordDraft, TimelineRecord } from '../../../domain/types';
import {
  createMediaService,
  MediaServiceError,
  removeUnreferencedMedia,
  saveRecordWithMedia,
  updateRecordWithMedia,
  type MediaFileSystem,
  type MediaService,
  type StagedMedia,
} from '../mediaService';

jest.mock('expo-file-system', () => ({
  Directory: jest.fn(),
  File: jest.fn(),
  Paths: { document: { uri: 'file:///documents/' }, availableDiskSpace: 10_000 },
}));
jest.mock('expo-image-manipulator', () => ({
  ImageManipulator: { manipulate: jest.fn() },
  SaveFormat: { JPEG: 'jpeg' },
}));

const imageDraft: RecordDraft = {
  type: 'moment',
  occurredAt: '2026-08-01T09:30:00.000Z',
  note: null,
  details: null,
  attachments: [{ kind: 'picked', sourceUri: 'file:///picker/a.jpg', mediaType: 'image' }],
};

function createFileSystem(overrides: Partial<MediaFileSystem> = {}): jest.Mocked<MediaFileSystem> {
  return {
    documentDirectory: 'file:///documents/',
    availableDiskSpace: jest.fn(() => 10_000),
    fileSize: jest.fn(() => 1_000),
    ensureDirectory: jest.fn(async () => undefined),
    copy: jest.fn(async () => undefined),
    move: jest.fn(async () => undefined),
    delete: jest.fn(async () => undefined),
    exists: jest.fn(() => true),
    list: jest.fn(() => []),
    ...overrides,
  } as jest.Mocked<MediaFileSystem>;
}

describe('media service lifecycle', () => {
  test('stages and commits an image into private storage with a thumbnail', async () => {
    const fs = createFileSystem();
    const createThumbnail = jest.fn(async () => undefined);
    const service = createMediaService({
      fileSystem: fs,
      createId: () => 'media-id',
      createThumbnail,
    });

    const staged = await service.stage({ uri: 'file:///picker/a.jpg', mediaType: 'image' });
    expect(staged).toEqual({
      stagingPath: 'file:///documents/staging/media-id.jpg',
      finalPath: 'file:///documents/media/media-id.jpg',
      mediaType: 'image',
      thumbnailStagingPath: 'file:///documents/staging/media-id-thumb.jpg',
      thumbnailFinalPath: 'file:///documents/media/media-id-thumb.jpg',
    });
    expect(fs.copy).toHaveBeenCalledWith({
      from: 'file:///picker/a.jpg',
      to: 'file:///documents/staging/media-id.jpg',
    });
    expect(createThumbnail).toHaveBeenCalledWith({
      from: 'file:///documents/staging/media-id.jpg',
      to: 'file:///documents/staging/media-id-thumb.jpg',
    });

    await expect(service.commit(staged)).resolves.toEqual({
      filePath: 'file:///documents/media/media-id.jpg',
      thumbnailPath: 'file:///documents/media/media-id-thumb.jpg',
    });
    expect(fs.move).toHaveBeenNthCalledWith(1, {
      from: staged.stagingPath,
      to: staged.finalPath,
    });
    expect(fs.move).toHaveBeenNthCalledWith(2, {
      from: staged.thumbnailStagingPath,
      to: staged.thumbnailFinalPath,
    });
  });

  test('rejects a format outside the supported allowlist before copying', async () => {
    const fs = createFileSystem();
    const service = createMediaService({ fileSystem: fs, createId: () => 'unused' });

    await expect(service.stage({
      uri: 'file:///picker/archive.zip',
      mediaType: 'image',
    })).rejects.toMatchObject({ code: 'unsupported-format' });
    expect(fs.copy).not.toHaveBeenCalled();
  });

  test('returns a displayable error when private storage lacks space', async () => {
    const fs = createFileSystem({
      availableDiskSpace: jest.fn(() => 999),
      fileSize: jest.fn(() => 1_000),
    });
    const service = createMediaService({ fileSystem: fs, createId: () => 'unused' });

    await expect(service.stage({ uri: 'file:///picker/a.jpg', mediaType: 'image' }))
      .rejects.toEqual(new MediaServiceError('insufficient-space', '设备存储空间不足，请清理后重试'));
    expect(fs.copy).not.toHaveBeenCalled();
  });

  test('rolls back staging files and removes only unreferenced committed files', async () => {
    const fs = createFileSystem({
      list: jest.fn((directory) => directory.endsWith('/staging')
        ? ['file:///documents/staging/interrupted.jpg']
        : [
          'file:///documents/media/kept.jpg',
          'file:///documents/media/orphan.jpg',
        ]),
    });
    const service = createMediaService({ fileSystem: fs, createId: () => 'media-id' });
    const staged: StagedMedia = {
      stagingPath: 'file:///documents/staging/media-id.jpg',
      finalPath: 'file:///documents/media/media-id.jpg',
      mediaType: 'image',
      thumbnailStagingPath: 'file:///documents/staging/media-id-thumb.jpg',
      thumbnailFinalPath: 'file:///documents/media/media-id-thumb.jpg',
    };

    await service.rollback(staged);
    await service.removeOrphans(['file:///documents/media/kept.jpg']);

    expect(fs.delete).toHaveBeenCalledWith(staged.stagingPath);
    expect(fs.delete).toHaveBeenCalledWith(staged.thumbnailStagingPath);
    expect(fs.delete).toHaveBeenCalledWith('file:///documents/staging/interrupted.jpg');
    expect(fs.delete).toHaveBeenCalledWith('file:///documents/media/orphan.jpg');
    expect(fs.delete).not.toHaveBeenCalledWith('file:///documents/media/kept.jpg');
  });

  test('removes a moved main file when committing its thumbnail fails', async () => {
    const fs = createFileSystem({
      move: jest.fn()
        .mockResolvedValueOnce(undefined)
        .mockRejectedValueOnce(new Error('thumbnail move failed')),
    });
    const service = createMediaService({ fileSystem: fs, createId: () => 'unused' });
    const staged = stagedImage();

    await expect(service.commit(staged)).rejects.toThrow('thumbnail move failed');

    expect(fs.delete).toHaveBeenCalledWith(staged.finalPath);
  });
});

describe('record media transaction coordination', () => {
  test('writes predetermined final paths, commits files, then lets the database commit', async () => {
    const events: string[] = [];
    const staged = stagedImage();
    const media = createMockMedia(staged, events);
    const records = createRecordRepository(events);

    const saved = await saveRecordWithMedia(imageDraft, { records, media });

    expect(saved.attachments[0]).toMatchObject({
      filePath: staged.finalPath,
      thumbnailPath: staged.thumbnailFinalPath,
    });
    expect(events).toEqual(['stage', 'db-write', 'file-commit', 'db-commit']);
  });

  test('removes newly committed files when the database commit fails', async () => {
    const events: string[] = [];
    const staged = stagedImage();
    const media = createMockMedia(staged, events);
    const records = createRecordRepository(events, new Error('database commit failed'));

    await expect(saveRecordWithMedia(imageDraft, { records, media }))
      .rejects.toThrow('database commit failed');
    expect(media.remove).toHaveBeenCalledWith([
      staged.finalPath,
      staged.thumbnailFinalPath,
    ]);
  });

  test('rolls back the database and staging paths when a file commit fails', async () => {
    const events: string[] = [];
    const staged = stagedImage();
    const media = createMockMedia(staged, events);
    media.commit.mockImplementation(async () => {
      events.push('file-commit');
      throw new Error('file commit failed');
    });
    const records = createRecordRepository(events);

    await expect(saveRecordWithMedia(imageDraft, { records, media }))
      .rejects.toThrow('file commit failed');

    expect(events).toEqual(['stage', 'db-write', 'file-commit']);
    expect(media.rollback).toHaveBeenCalledWith(staged);
  });

  test('rolls back earlier staging files when a later pick cannot be staged', async () => {
    const events: string[] = [];
    const staged = stagedImage();
    const media = createMockMedia(staged, events);
    media.stage
      .mockResolvedValueOnce(staged)
      .mockRejectedValueOnce(new Error('second stage failed'));
    const records = createRecordRepository(events);
    const twoImages: RecordDraft = {
      ...imageDraft,
      attachments: [
        { kind: 'picked', sourceUri: 'file:///picker/a.jpg', mediaType: 'image' },
        { kind: 'picked', sourceUri: 'file:///picker/b.jpg', mediaType: 'image' },
      ],
    };

    await expect(saveRecordWithMedia(twoImages, { records, media }))
      .rejects.toThrow('second stage failed');

    expect(media.rollback).toHaveBeenCalledWith(staged);
    expect(events).not.toContain('db-write');
  });

  test('updates attachment indexes before commit and removes replaced old media only afterward', async () => {
    const events: string[] = [];
    const staged = stagedImage();
    const media = createMockMedia(staged, events);
    const old = timelineRecord({
      attachments: [{
        id: 'old-attachment',
        recordId: 'record-1',
        mediaType: 'image',
        filePath: 'file:///documents/media/old.jpg',
        thumbnailPath: 'file:///documents/media/old-thumb.jpg',
        createdAt: '2026-07-01T00:00:00.000Z',
      }],
    });
    const records = createRecordRepository(events, undefined, old);

    await updateRecordWithMedia('record-1', imageDraft, { records, media });

    expect(events).toEqual([
      'record-load',
      'stage',
      'db-write',
      'file-commit',
      'db-commit',
      'file-remove',
    ]);
    expect(media.remove).toHaveBeenLastCalledWith([
      'file:///documents/media/old.jpg',
      'file:///documents/media/old-thumb.jpg',
    ]);
  });

  test('preserves old update media when the database commit fails', async () => {
    const events: string[] = [];
    const staged = stagedImage();
    const media = createMockMedia(staged, events);
    const old = timelineRecord({
      attachments: [{
        id: 'old-attachment',
        recordId: 'record-1',
        mediaType: 'image',
        filePath: 'file:///documents/media/old.jpg',
        thumbnailPath: null,
        createdAt: '2026-07-01T00:00:00.000Z',
      }],
    });
    const records = createRecordRepository(events, new Error('database commit failed'), old);

    await expect(updateRecordWithMedia('record-1', imageDraft, { records, media }))
      .rejects.toThrow('database commit failed');

    expect(media.remove).toHaveBeenCalledWith([
      staged.finalPath,
      staged.thumbnailFinalPath,
    ]);
    expect(media.remove).not.toHaveBeenCalledWith(['file:///documents/media/old.jpg']);
  });
});

test('orphan cleanup collects baby avatar, attachment, and thumbnail references', async () => {
  const media = createMockMedia(stagedImage(), []);
  const babyRepository: BabyRepository = {
    get: jest.fn(async () => ({
      id: 'baby-1',
      name: '安安',
      birthDate: '2025-06-15',
      sex: null,
      avatarPath: 'file:///documents/media/avatar.jpg',
      createdAt: '2026-07-01T00:00:00.000Z',
      updatedAt: '2026-07-01T00:00:00.000Z',
    })),
    save: jest.fn(),
    clear: jest.fn(),
  };
  const records = createRecordRepository([], undefined, null);
  records.list = jest.fn(async () => [timelineRecord({
    attachments: [{
      id: 'attachment-1',
      recordId: 'record-1',
      mediaType: 'image',
      filePath: 'file:///documents/media/photo.jpg',
      thumbnailPath: 'file:///documents/media/photo-thumb.jpg',
      createdAt: '2026-07-01T00:00:00.000Z',
    }],
  })]);

  await removeUnreferencedMedia({ babies: babyRepository, records, media });

  expect(media.removeOrphans).toHaveBeenCalledWith([
    'file:///documents/media/avatar.jpg',
    'file:///documents/media/photo.jpg',
    'file:///documents/media/photo-thumb.jpg',
  ]);
});

function stagedImage(): StagedMedia {
  return {
    stagingPath: 'file:///documents/staging/new.jpg',
    finalPath: 'file:///documents/media/new.jpg',
    mediaType: 'image',
    thumbnailStagingPath: 'file:///documents/staging/new-thumb.jpg',
    thumbnailFinalPath: 'file:///documents/media/new-thumb.jpg',
  };
}

function createMockMedia(
  staged: StagedMedia,
  events: string[],
): jest.Mocked<MediaService> {
  return {
    stage: jest.fn(async (_input: { uri: string; mediaType: 'image' | 'video' }) => {
      events.push('stage');
      return staged;
    }),
    commit: jest.fn(async (_staged: StagedMedia) => {
      events.push('file-commit');
      return { filePath: staged.finalPath, thumbnailPath: staged.thumbnailFinalPath };
    }),
    rollback: jest.fn(async (_staged: StagedMedia) => undefined),
    remove: jest.fn(async (_paths: string[]) => {
      events.push('file-remove');
    }),
    removeOrphans: jest.fn(async (_referencedPaths: string[]) => undefined),
  };
}

function createRecordRepository(
  events: string[],
  commitError?: Error,
  existing: TimelineRecord | null = null,
): RecordRepository {
  const write = async (input: NewRecordInput) => {
    events.push('db-write');
    return timelineRecord({
      attachments: input.attachments.map((attachment, index) => ({
        id: attachment.id ?? `attachment-${index}`,
        recordId: 'record-1',
        mediaType: attachment.mediaType,
        filePath: attachment.filePath,
        thumbnailPath: attachment.thumbnailPath,
        createdAt: '2026-08-01T09:30:00.000Z',
      })),
    });
  };
  const transaction: RecordTransaction = {
    create: write,
    update: async (_id, input) => write(input),
    delete: jest.fn(async () => []),
  };

  return {
    create: transaction.create,
    update: transaction.update,
    delete: transaction.delete,
    list: jest.fn(async () => []),
    get: jest.fn(async () => {
      events.push('record-load');
      return existing;
    }),
    withTransaction: async (work) => {
      const value = await work(transaction);
      if (commitError !== undefined) {
        throw commitError;
      }
      events.push('db-commit');
      return value;
    },
  };
}

function timelineRecord(overrides: Partial<TimelineRecord> = {}): TimelineRecord {
  return {
    id: 'record-1',
    type: 'moment',
    occurredAt: '2026-08-01T09:30:00.000Z',
    note: null,
    details: null,
    attachments: [],
    createdAt: '2026-08-01T09:30:00.000Z',
    updatedAt: '2026-08-01T09:30:00.000Z',
    ...overrides,
  };
}
