import type { BabyRepository, RecordRepository } from '../../../data/repositories';
import type { DatabaseManager } from '../../../data/database';
import type { MediaService } from '../../media/mediaService';
import { openDatabaseAsync, type SQLiteDatabase } from 'expo-sqlite';
import {
  createBackupService,
  readZipCentralDirectory,
  validateSQLiteDatabaseFile,
  type BackupArchive,
  type BackupArchiveEntry,
  type BackupFileSystem,
} from '../backupService';

jest.mock('expo-sqlite', () => ({
  openDatabaseAsync: jest.fn(),
}));

const openDatabase = openDatabaseAsync as jest.MockedFunction<typeof openDatabaseAsync>;

const OLD_DATABASE = bytes('old database');
const BACKUP_DATABASE = bytes('backup database');
const PHOTO = bytes('photo bytes');
const DATABASE_HASH = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const PHOTO_HASH = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const OLD_DATABASE_HASH = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';

describe('BackupService export', () => {
  test('exports a closed SQLite snapshot and referenced media with a versioned manifest', async () => {
    const fixture = createFixture();
    let archivedManifest: unknown;
    fixture.archive.zip.mockImplementation(async (sourceDirectory, targetPath) => {
      archivedManifest = JSON.parse(await fixture.fileSystem.readText(
        `${sourceDirectory}/manifest.json`,
      ));
      fixture.fileSystem.seedFile(targetPath, bytes('zip'));
    });

    const result = await fixture.service.export();

    expect(fixture.database.withClosedDatabase).toHaveBeenCalledTimes(1);
    expect(archivedManifest).toEqual({
      format: 'baby-growth-backup',
      version: 1,
      createdAt: '2026-08-01T12:00:00.000Z',
      database: {
        path: 'database/app.db',
        sha256: OLD_DATABASE_HASH,
      },
      media: [{
        path: 'media/photo.jpg',
        sha256: PHOTO_HASH,
        size: PHOTO.length,
      }],
    });
    expect(result.archivePath).toMatch(/\.babygrowth\.zip$/);
    expect(result.shared).toBe(true);
    expect(fixture.sharing.share).toHaveBeenCalledWith(result.archivePath);
  });

  test('rejects a referenced media file that is missing instead of emitting a partial backup', async () => {
    const fixture = createFixture();
    fixture.fileSystem.deleteNow('file:///documents/media/photo.jpg');

    await expect(fixture.service.export()).rejects.toMatchObject({
      name: 'BackupServiceError',
      stage: 'files',
    });

    expect(fixture.archive.zip).not.toHaveBeenCalled();
    expect(fixture.sharing.share).not.toHaveBeenCalled();
  });

  test('keeps the archive and returns its path when system sharing is unavailable', async () => {
    const fixture = createFixture();
    fixture.sharing.isAvailable.mockResolvedValue(false);

    const result = await fixture.service.export();

    expect(result).toMatchObject({ shared: false });
    expect(fixture.fileSystem.exists(result.archivePath)).toBe(true);
    expect(fixture.sharing.share).not.toHaveBeenCalled();
  });

  test('removes a partial current archive when native ZIP creation fails', async () => {
    const fixture = createFixture();
    fixture.archive.zip.mockImplementation(async (_source, target) => {
      fixture.fileSystem.seedFile(target, bytes('partial zip'));
      throw new Error('zip failed midway');
    });

    await expect(fixture.service.export()).rejects.toThrow('zip failed midway');

    expect(fixture.fileSystem.list('file:///cache/backup-exports')).toEqual([]);
  });
});

describe('BackupService inspection', () => {
  test.each([
    '/absolute.txt',
    '../outside.txt',
    'media/../../outside.txt',
    'C:\\outside.txt',
    'media\\..\\outside.txt',
    'media/bad\0name.jpg',
  ])('rejects unsafe central-directory path %p before native extraction', async (unsafePath) => {
    const fixture = createFixture();
    fixture.archive.listEntries.mockResolvedValue([
      ...safeArchiveEntries(),
      archiveEntry(unsafePath),
    ]);

    await expect(fixture.service.inspect('file:///picker/unsafe.zip')).rejects.toMatchObject({
      stage: 'archive',
    });

    expect(fixture.archive.unzip).not.toHaveBeenCalled();
  });

  test('rejects a central/local-header filename mismatch before native extraction', () => {
    const archive = zipFixture([
      { centralPath: 'manifest.json', localPath: '../manifest.json' },
    ]);

    expect(() => readZipCentralDirectory(archive)).toThrow('local header');
  });

  test('rejects duplicate names and symbolic links before native extraction', async () => {
    const duplicate = createFixture();
    duplicate.archive.listEntries.mockResolvedValue([
      ...safeArchiveEntries(),
      archiveEntry('media/PHOTO.jpg'),
    ]);
    await expect(duplicate.service.inspect('file:///picker/duplicate.zip')).rejects.toMatchObject({
      stage: 'archive',
    });
    expect(duplicate.archive.unzip).not.toHaveBeenCalled();

    const symlink = createFixture();
    symlink.archive.listEntries.mockResolvedValue([
      ...safeArchiveEntries(),
      { ...archiveEntry('media/link'), isSymbolicLink: true },
    ]);
    await expect(symlink.service.inspect('file:///picker/symlink.zip')).rejects.toMatchObject({
      stage: 'archive',
    });
    expect(symlink.archive.unzip).not.toHaveBeenCalled();
  });

  test('rejects Unicode-normalized filename collisions before native extraction', async () => {
    const fixture = createFixture();
    fixture.archive.listEntries.mockResolvedValue([
      ...safeArchiveEntries(),
      archiveEntry('media/cafe\u0301.jpg'),
      archiveEntry('media/caf\u00e9.jpg'),
    ]);

    await expect(fixture.service.inspect('file:///picker/unicode-collision.zip'))
      .rejects.toMatchObject({ stage: 'archive' });
    expect(fixture.archive.unzip).not.toHaveBeenCalled();
  });

  test('rejects an unsupported manifest version without closing the current database', async () => {
    const fixture = createFixture({ manifestVersion: 2 });

    await expect(fixture.service.restore('file:///picker/version-2.zip')).rejects.toMatchObject({
      stage: 'manifest',
    });

    expect(fixture.database.withClosedDatabase).not.toHaveBeenCalled();
  });

  test('rejects missing payload entries and hash or size mismatches before replacement', async () => {
    const missing = createFixture();
    missing.archive.listEntries.mockResolvedValue(
      safeArchiveEntries().filter((entry) => entry.path !== 'media/photo.jpg'),
    );
    await expect(missing.service.restore('file:///picker/missing.zip')).rejects.toMatchObject({
      stage: 'files',
    });
    expect(missing.database.withClosedDatabase).not.toHaveBeenCalled();

    const wrongHash = createFixture({
      mediaHash: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
    });
    await expect(wrongHash.service.restore('file:///picker/hash.zip')).rejects.toMatchObject({
      stage: 'files',
    });
    expect(wrongHash.database.withClosedDatabase).not.toHaveBeenCalled();

    const wrongSize = createFixture({ mediaSize: PHOTO.length + 1 });
    await expect(wrongSize.service.restore('file:///picker/size.zip')).rejects.toMatchObject({
      stage: 'files',
    });
    expect(wrongSize.database.withClosedDatabase).not.toHaveBeenCalled();
  });

  test('rejects a corrupt SQLite payload before replacement and always closes its inspector', async () => {
    const fixture = createFixture();
    fixture.validateDatabase.mockRejectedValue(new Error('integrity_check failed'));

    await expect(fixture.service.restore('file:///picker/corrupt.zip')).rejects.toMatchObject({
      stage: 'integrity',
    });

    expect(fixture.database.withClosedDatabase).not.toHaveBeenCalled();
  });
});

describe('BackupService restore', () => {
  test('validates the complete archive before replacing the closed database and media', async () => {
    const fixture = createFixture();
    fixture.fileSystem.seedFile('/sqlite/app.db-wal', bytes('old wal'));
    fixture.fileSystem.seedFile('/sqlite/app.db-shm', bytes('old shm'));
    fixture.fileSystem.seedFile(
      'file:///documents/media.restore-restore-id/stale.jpg',
      bytes('stale candidate'),
    );

    await expect(fixture.service.restore('file:///picker/valid.zip')).resolves.toMatchObject({
      status: 'restored',
    });

    expect(fixture.validateDatabase).toHaveBeenCalledWith(
      expect.stringMatching(/\/extracted\/database\/app\.db$/),
      new Map([['media/photo.jpg', 'file:///documents/media/photo.jpg']]),
    );
    expect(fixture.fileSystem.readBytes('/sqlite/app.db')).resolves.toEqual(BACKUP_DATABASE);
    expect(fixture.fileSystem.readBytes('file:///documents/media/photo.jpg')).resolves.toEqual(PHOTO);
    expect(fixture.events).toEqual(expect.arrayContaining([
      'archive-list',
      'archive-unzip',
      'database-integrity',
      'database-close-current',
    ]));
    expect(fixture.events.indexOf('database-integrity')).toBeLessThan(
      fixture.events.indexOf('database-close-current'),
    );
    expect(fixture.fileSystem.exists('/sqlite/app.db-wal')).toBe(false);
    expect(fixture.fileSystem.exists('/sqlite/app.db-shm')).toBe(false);
    expect(fixture.fileSystem.exists('file:///documents/media/stale.jpg')).toBe(false);
  });

  test('restores both old database and old media when replacement fails midway', async () => {
    const fixture = createFixture();
    fixture.fileSystem.deleteNow('file:///documents/media/photo.jpg');
    fixture.fileSystem.seedFile('/sqlite/app.db-wal', bytes('old wal'));
    fixture.fileSystem.seedFile('/sqlite/app.db-shm', bytes('old shm'));
    fixture.fileSystem.failMoveTo('file:///documents/media', new Error('install media failed'));

    await expect(fixture.service.restore('file:///picker/valid.zip')).rejects.toMatchObject({
      stage: 'replace',
    });

    await expect(fixture.fileSystem.readBytes('/sqlite/app.db')).resolves.toEqual(OLD_DATABASE);
    await expect(fixture.fileSystem.readBytes('file:///documents/media/old.jpg'))
      .resolves.toEqual(bytes('old photo'));
    await expect(fixture.fileSystem.readBytes('/sqlite/app.db-wal')).resolves.toEqual(bytes('old wal'));
    await expect(fixture.fileSystem.readBytes('/sqlite/app.db-shm')).resolves.toEqual(bytes('old shm'));
    expect(fixture.fileSystem.exists('file:///documents/media/photo.jpg')).toBe(false);
  });

  test('surfaces rollback errors together with the replacement error', async () => {
    const fixture = createFixture();
    fixture.fileSystem.failMoveTo('file:///documents/media', new Error('install media failed'));
    fixture.fileSystem.failMoveFromMatching(/app\.db\.rollback-restore-id$/, new Error('database rollback failed'));

    await expect(fixture.service.restore('file:///picker/valid.zip')).rejects.toMatchObject({
      name: 'AggregateError',
      errors: expect.arrayContaining([
        expect.objectContaining({ message: 'install media failed' }),
        expect.objectContaining({ message: 'database rollback failed' }),
      ]),
    });
  });
});

describe('BackupService clear', () => {
  test('commits an empty database first and reports cleanup pending if post-delete media cleanup fails', async () => {
    const fixture = createFixture();
    fixture.media.remove.mockRejectedValue(new Error('media is locked'));

    const result = await fixture.service.clear();

    expect(result.cleanupPending).toBe(true);
    expect(fixture.media.removeOrphans).toHaveBeenCalledWith([]);
    expect(fixture.fileSystem.exists('/sqlite/app.db')).toBe(false);
  });

  test('can clear a database containing a stale external media reference', async () => {
    const fixture = createFixture();
    fixture.records.list = jest.fn<
      ReturnType<RecordRepository['list']>,
      Parameters<RecordRepository['list']>
    >(async () => [{
      id: 'record-external',
      type: 'moment',
      occurredAt: '2026-08-01T08:00:00.000Z',
      note: null,
      details: null,
      attachments: [{
        id: 'attachment-external',
        recordId: 'record-external',
        mediaType: 'image',
        filePath: 'file:///outside/photo.jpg',
        thumbnailPath: null,
        createdAt: '2026-08-01T08:00:00.000Z',
      }],
      createdAt: '2026-08-01T08:00:00.000Z',
      updatedAt: '2026-08-01T08:00:00.000Z',
    }]);

    await expect(fixture.service.clear()).resolves.toMatchObject({ cleanupPending: false });
    expect(fixture.media.remove).toHaveBeenCalledWith(['file:///outside/photo.jpg']);
  });
});

test('SQLite inspection checkpoints remapped WAL changes before closing the temporary database', async () => {
  const events: string[] = [];
  const database = {
    execAsync: jest.fn(async (sql: string) => {
      events.push(sql);
    }),
    getFirstAsync: jest.fn(async (sql: string) => (
      sql.includes('integrity_check') ? { integrity_check: 'ok' } : { user_version: 1 }
    )),
    getAllAsync: jest.fn(async () => []),
    runAsync: jest.fn(),
    closeAsync: jest.fn(async () => {
      events.push('close');
    }),
  };
  openDatabase.mockResolvedValueOnce(database as unknown as SQLiteDatabase);

  await validateSQLiteDatabaseFile(
    'file:///cache/extracted/database/app.db',
    new Map(),
    openDatabase,
  );

  expect(events).toContain('PRAGMA wal_checkpoint(TRUNCATE);');
  expect(events.indexOf('PRAGMA wal_checkpoint(TRUNCATE);')).toBeLessThan(events.indexOf('close'));
});

type FixtureOptions = {
  manifestVersion?: number;
  mediaHash?: string;
  mediaSize?: number;
};

function createFixture(options: FixtureOptions = {}) {
  const events: string[] = [];
  const fileSystem = new MemoryBackupFileSystem();
  fileSystem.seedFile('/sqlite/app.db', OLD_DATABASE);
  fileSystem.seedFile('file:///documents/media/old.jpg', bytes('old photo'));
  fileSystem.seedFile('file:///documents/media/photo.jpg', PHOTO);
  const withClosedDatabase = jest.fn(async (work: (databasePath: string) => Promise<unknown>) => {
    events.push('database-close-current');
    try {
      return await work('/sqlite/app.db');
    } finally {
      events.push('database-reopen');
    }
  });
  const database: DatabaseManager = {
    initialize: jest.fn(),
    reopen: jest.fn(async () => {
      events.push('database-reopen');
      return {} as never;
    }),
    withClosedDatabase: withClosedDatabase as DatabaseManager['withClosedDatabase'],
  };
  const babies: BabyRepository = {
    get: jest.fn(async () => ({
      id: 'baby-1',
      name: '安安',
      birthDate: '2025-06-15',
      sex: null,
      avatarPath: null,
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    })),
    save: jest.fn(),
    clear: jest.fn(),
  };
  const records: RecordRepository = {
    create: jest.fn(),
    update: jest.fn(),
    delete: jest.fn(),
    get: jest.fn(),
    withTransaction: jest.fn(),
    list: jest.fn<ReturnType<RecordRepository['list']>, Parameters<RecordRepository['list']>>(
      async () => [{
      id: 'record-1',
      type: 'moment',
      occurredAt: '2026-08-01T08:00:00.000Z',
      note: null,
      details: null,
      attachments: [{
        id: 'attachment-1',
        recordId: 'record-1',
        mediaType: 'image',
        filePath: 'file:///documents/media/photo.jpg',
        thumbnailPath: null,
        createdAt: '2026-08-01T08:00:00.000Z',
      }],
      createdAt: '2026-08-01T08:00:00.000Z',
      updatedAt: '2026-08-01T08:00:00.000Z',
      }],
    ),
  };
  const media: jest.Mocked<MediaService> = {
    stage: jest.fn(),
    commit: jest.fn(),
    rollback: jest.fn(),
    remove: jest.fn<Promise<void>, [string[]]>(async () => undefined),
    removeOrphans: jest.fn<Promise<void>, [string[]]>(async () => undefined),
  };
  const manifest = {
    format: 'baby-growth-backup',
    version: options.manifestVersion ?? 1,
    createdAt: '2026-08-01T12:00:00.000Z',
    database: { path: 'database/app.db', sha256: DATABASE_HASH },
    media: [{
      path: 'media/photo.jpg',
      sha256: options.mediaHash ?? PHOTO_HASH,
      size: options.mediaSize ?? PHOTO.length,
    }],
  };
  const archive: jest.Mocked<BackupArchive> = {
    listEntries: jest.fn<Promise<BackupArchiveEntry[]>, [string]>(async () => {
      events.push('archive-list');
      return safeArchiveEntries();
    }),
    unzip: jest.fn(async (_source, target) => {
      events.push('archive-unzip');
      fileSystem.seedFile(`${target}/manifest.json`, bytes(JSON.stringify(manifest)));
      fileSystem.seedFile(`${target}/database/app.db`, BACKUP_DATABASE);
      fileSystem.seedFile(`${target}/media/photo.jpg`, PHOTO);
    }),
    zip: jest.fn(async (_source, target) => {
      fileSystem.seedFile(target, bytes('zip'));
    }),
  };
  const sharing = {
    isAvailable: jest.fn(async () => true),
    share: jest.fn(async (_path: string) => undefined),
  };
  const validateDatabase = jest.fn(async () => {
    events.push('database-integrity');
  });
  const hashFile = jest.fn(async (path: string) => {
    const contents = text(await fileSystem.readBytes(path));
    if (contents === 'backup database') {
      return DATABASE_HASH;
    }
    if (contents === 'old database') {
      return OLD_DATABASE_HASH;
    }
    if (contents === 'photo bytes') {
      return PHOTO_HASH;
    }
    return 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
  });
  const service = createBackupService({
    archive,
    babies,
    createId: () => 'restore-id',
    database,
    fileSystem,
    hashFile,
    media,
    now: () => new Date('2026-08-01T12:00:00.000Z'),
    pickArchive: jest.fn(async () => 'file:///picker/valid.zip'),
    records,
    sharing,
    validateDatabase,
  });

  return {
    archive,
    babies,
    database,
    events,
    fileSystem,
    media,
    records,
    service,
    sharing,
    validateDatabase,
  };
}

class MemoryBackupFileSystem implements BackupFileSystem {
  readonly cacheDirectory = 'file:///cache';
  readonly documentDirectory = 'file:///documents';
  private readonly files = new Map<string, Uint8Array>();
  private readonly directories = new Set<string>([
    'file:///cache',
    'file:///documents',
    'file:///documents/media',
    '/sqlite',
  ]);
  private readonly moveToFailures = new Map<string, Error>();
  private readonly moveFromFailures: Array<{ pattern: RegExp; error: Error }> = [];

  availableDiskSpace = jest.fn(() => 1_000_000);

  seedFile(path: string, value: Uint8Array): void {
    this.ensureParents(path);
    this.files.set(path, value.slice());
  }

  deleteNow(path: string): void {
    this.files.delete(path);
    this.directories.delete(path);
  }

  failMoveTo(path: string, error: Error): void {
    this.moveToFailures.set(path, error);
  }

  failMoveFromMatching(pattern: RegExp, error: Error): void {
    this.moveFromFailures.push({ pattern, error });
  }

  exists = jest.fn((path: string) => this.files.has(path) || this.directories.has(path));
  size = jest.fn((path: string) => this.files.get(path)?.length ?? 0);
  readBytes = jest.fn(async (path: string) => {
    const value = this.files.get(path);
    if (value === undefined) {
      throw new Error(`Missing file: ${path}`);
    }
    return value.slice();
  });
  readText = jest.fn(async (path: string) => text(await this.readBytes(path)));
  writeText = jest.fn(async (path: string, value: string) => {
    this.seedFile(path, bytes(value));
  });
  ensureDirectory = jest.fn(async (path: string) => {
    this.ensureParents(path);
    this.directories.add(path);
  });
  copyFile = jest.fn(async (source: string, target: string) => {
    this.seedFile(target, await this.readBytes(source));
  });
  move = jest.fn(async (source: string, target: string) => {
    const fromFailure = this.moveFromFailures.find(({ pattern }) => pattern.test(source));
    if (fromFailure !== undefined) {
      throw fromFailure.error;
    }
    const toFailure = this.moveToFailures.get(target);
    if (toFailure !== undefined) {
      this.moveToFailures.delete(target);
      throw toFailure;
    }
    if (this.files.has(source)) {
      const value = this.files.get(source)!;
      this.files.delete(source);
      this.seedFile(target, value);
      return;
    }
    if (!this.directories.has(source)) {
      throw new Error(`Missing path: ${source}`);
    }
    const nestedFiles = [...this.files.entries()].filter(([path]) => path.startsWith(`${source}/`));
    const nestedDirectories = [...this.directories].filter((path) => path.startsWith(`${source}/`));
    this.directories.delete(source);
    this.directories.add(target);
    for (const [path, value] of nestedFiles) {
      this.files.delete(path);
      this.seedFile(`${target}${path.slice(source.length)}`, value);
    }
    for (const path of nestedDirectories) {
      this.directories.delete(path);
      this.directories.add(`${target}${path.slice(source.length)}`);
    }
  });
  delete = jest.fn(async (path: string) => {
    this.files.delete(path);
    for (const file of [...this.files.keys()]) {
      if (file.startsWith(`${path}/`)) {
        this.files.delete(file);
      }
    }
    this.directories.delete(path);
    for (const directory of [...this.directories]) {
      if (directory.startsWith(`${path}/`)) {
        this.directories.delete(directory);
      }
    }
  });
  list = jest.fn((directory: string) => [...this.files.keys()]
    .filter((path) => parent(path) === directory)
    .map((path) => ({ path, modifiedAt: 0 })));

  private ensureParents(path: string): void {
    let current = parent(path);
    while (current !== '' && current !== path) {
      this.directories.add(current);
      const next = parent(current);
      if (next === current) {
        return;
      }
      current = next;
    }
  }
}

function safeArchiveEntries(): BackupArchiveEntry[] {
  return [
    archiveEntry('manifest.json', 200),
    archiveEntry('database/app.db', BACKUP_DATABASE.length),
    archiveEntry('media/photo.jpg', PHOTO.length),
  ];
}

function archiveEntry(path: string, uncompressedSize = 1): BackupArchiveEntry {
  return {
    path,
    compressedSize: uncompressedSize,
    uncompressedSize,
    isDirectory: false,
    isSymbolicLink: false,
  };
}

function bytes(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

function text(value: Uint8Array): string {
  return new TextDecoder().decode(value);
}

function parent(path: string): string {
  const index = path.lastIndexOf('/');
  return index <= 0 ? path.slice(0, Math.max(0, index)) : path.slice(0, index);
}

function zipFixture(entries: Array<{ centralPath: string; localPath: string }>): Uint8Array {
  const chunks: number[] = [];
  const central: number[] = [];
  const offsets: number[] = [];
  for (const entry of entries) {
    offsets.push(chunks.length);
    const name = [...bytes(entry.localPath)];
    pushU32(chunks, 0x04034b50);
    pushU16(chunks, 20);
    pushU16(chunks, 0x0800);
    pushU16(chunks, 0);
    pushU16(chunks, 0);
    pushU16(chunks, 0);
    pushU32(chunks, 0);
    pushU32(chunks, 0);
    pushU32(chunks, 0);
    pushU16(chunks, name.length);
    pushU16(chunks, 0);
    chunks.push(...name);
  }
  const centralOffset = chunks.length;
  entries.forEach((entry, index) => {
    const name = [...bytes(entry.centralPath)];
    pushU32(central, 0x02014b50);
    pushU16(central, 20);
    pushU16(central, 20);
    pushU16(central, 0x0800);
    pushU16(central, 0);
    pushU16(central, 0);
    pushU16(central, 0);
    pushU32(central, 0);
    pushU32(central, 0);
    pushU32(central, 0);
    pushU16(central, name.length);
    pushU16(central, 0);
    pushU16(central, 0);
    pushU16(central, 0);
    pushU16(central, 0);
    pushU32(central, 0);
    pushU32(central, offsets[index]);
    central.push(...name);
  });
  chunks.push(...central);
  pushU32(chunks, 0x06054b50);
  pushU16(chunks, 0);
  pushU16(chunks, 0);
  pushU16(chunks, entries.length);
  pushU16(chunks, entries.length);
  pushU32(chunks, central.length);
  pushU32(chunks, centralOffset);
  pushU16(chunks, 0);
  return new Uint8Array(chunks);
}

function pushU16(target: number[], value: number): void {
  target.push(value & 0xff, (value >>> 8) & 0xff);
}

function pushU32(target: number[], value: number): void {
  pushU16(target, value & 0xffff);
  pushU16(target, (value >>> 16) & 0xffff);
}
