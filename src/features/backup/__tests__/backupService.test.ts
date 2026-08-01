import type { BabyRepository, RecordRepository } from '../../../data/repositories';
import {
  DatabaseRecoveryRequiredError,
  type DatabaseManager,
} from '../../../data/database';
import type { MediaService } from '../../media/mediaService';
import { createMaintenanceCoordinator } from '../../../app/maintenance';
import { openDatabaseAsync, type SQLiteDatabase } from 'expo-sqlite';
import {
  createBackupService,
  readZipCentralDirectory,
  sha256File,
  validateSQLiteDatabaseFile,
  type BackupArchive,
  type BackupArchiveEntry,
  type BackupFileReader,
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

  test('rejects encoded traversal in a stored private-media reference before export', async () => {
    const fixture = createFixture();
    const unsafePath = 'file:///documents/media/%252e%252e%252foutside.jpg';
    fixture.fileSystem.seedFile(unsafePath, bytes('outside'));
    fixture.readSnapshotMediaPaths.mockResolvedValue([unsafePath]);

    await expect(fixture.service.export()).rejects.toMatchObject({
      name: 'BackupServiceError',
      stage: 'files',
    });

    expect(fixture.archive.zip).not.toHaveBeenCalled();
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

  test('derives media references from the copied snapshot when live repositories mutate', async () => {
    const fixture = createFixture();
    fixture.fileSystem.seedFile(
      'file:///documents/media/live-only.jpg',
      bytes('live-only photo'),
    );
    jest.mocked(fixture.records.list).mockResolvedValue([{
      id: 'record-live',
      type: 'moment',
      occurredAt: '2026-08-01T09:00:00.000Z',
      note: null,
      details: null,
      attachments: [{
        id: 'attachment-live',
        recordId: 'record-live',
        mediaType: 'image',
        filePath: 'file:///documents/media/live-only.jpg',
        thumbnailPath: null,
        createdAt: '2026-08-01T09:00:00.000Z',
      }],
      createdAt: '2026-08-01T09:00:00.000Z',
      updatedAt: '2026-08-01T09:00:00.000Z',
    }]);
    jest.mocked(fixture.babies.get).mockClear();
    jest.mocked(fixture.records.list).mockClear();
    let archivedManifest: { media?: Array<{ path: string }> } = {};
    fixture.archive.zip.mockImplementation(async (sourceDirectory, targetPath) => {
      archivedManifest = JSON.parse(await fixture.fileSystem.readText(
        `${sourceDirectory}/manifest.json`,
      )) as typeof archivedManifest;
      fixture.fileSystem.seedFile(targetPath, bytes('zip'));
    });

    await fixture.service.export();

    expect(archivedManifest.media).toEqual([{ path: 'media/photo.jpg', sha256: PHOTO_HASH, size: PHOTO.length }]);
    expect(fixture.readSnapshotMediaPaths).toHaveBeenCalledWith(expect.stringMatching(
      /backup-work\/export-restore-id\/database\/app\.db$/,
    ));
    expect(fixture.babies.get).not.toHaveBeenCalled();
    expect(fixture.records.list).not.toHaveBeenCalled();
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
    'media/%2e%2e%2foutside.jpg',
    'media/%252e%252e%252foutside.jpg',
    'media/folder%2Fphoto.jpg',
    'media/folder%255Cphoto.jpg',
    'media/%70hoto.jpg',
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

  test('rejects a central/local-header filename mismatch before native extraction', async () => {
    const archive = zipFixture([
      { centralPath: 'manifest.json', localPath: '../manifest.json' },
    ]);

    await expect(readZipCentralDirectory(memoryReader(archive))).rejects.toThrow('local header');
  });

  test.each([
    ['flags', { localFlags: 0, centralFlags: 0x0800 }],
    ['compression method', { localMethod: 8, centralMethod: 0 }],
    ['CRC', { localCrc: 1, centralCrc: 0 }],
    ['compressed size', { localCompressedSize: 1, centralCompressedSize: 0 }],
    ['uncompressed size', { localUncompressedSize: 1, centralUncompressedSize: 0 }],
  ])('rejects local/central %s disagreement before native extraction', async (reason, fields) => {
    const archive = zipFixture([{
      centralPath: 'manifest.json',
      localPath: 'manifest.json',
      ...fields,
    }]);

    await expect(readZipCentralDirectory(memoryReader(archive))).rejects.toThrow(reason);
  });

  test('accepts the forced ZIP64 size fields emitted by the iOS exporter', async () => {
    const payload = [0x61, 0x62, 0x63];
    const sizes = zip64Extra([payload.length, payload.length]);
    const archive = zipFixture([{
      centralPath: 'manifest.json',
      localPath: 'manifest.json',
      centralCompressedSize: 0xffffffff,
      centralUncompressedSize: 0xffffffff,
      localCompressedSize: 0xffffffff,
      localUncompressedSize: 0xffffffff,
      centralExtra: sizes,
      localExtra: sizes,
      data: payload,
    }]);

    await expect(readZipCentralDirectory(memoryReader(archive))).resolves.toEqual([
      expect.objectContaining({
        path: 'manifest.json',
        compressedSize: 3,
        uncompressedSize: 3,
      }),
    ]);
  });

  test.each([
    ['central', { centralExtra: [0x01, 0x00, 0x00, 0x00] }],
    ['local', { localExtra: [0x01, 0x00, 0x00, 0x00] }],
    ['central sentinel', { centralCompressedSize: 0xffffffff }],
    ['local sentinel', { localCompressedSize: 0xffffffff }],
  ])('rejects ZIP64 data in the %s header', async (_label, fields) => {
    const archive = zipFixture([{
      centralPath: 'manifest.json',
      localPath: 'manifest.json',
      ...fields,
    }]);

    await expect(readZipCentralDirectory(memoryReader(archive))).rejects.toThrow('ZIP64');
  });

  test('rejects a truncated ZIP extra field before native extraction', async () => {
    const archive = zipFixture([{
      centralPath: 'manifest.json',
      localPath: 'manifest.json',
      centralExtra: [0x02, 0x00, 0x08, 0x00],
    }]);

    await expect(readZipCentralDirectory(memoryReader(archive))).rejects.toThrow('extra field');
  });

  test('parses a sparse large archive using bounded random-access reads', async () => {
    const { reader, readLengths } = sparseZipReader(64 * 1024 * 1024);

    await expect(readZipCentralDirectory(reader)).resolves.toEqual([
      expect.objectContaining({ path: 'manifest.json' }),
    ]);

    expect(Math.max(...readLengths)).toBeLessThanOrEqual(65_557);
    expect(readLengths).not.toContain(reader.size);
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
  test('pre-arms a recovery journal before the first restore rename', async () => {
    const fixture = createFixture();

    await fixture.service.restore('file:///picker/valid.zip');

    expect(fixture.database.withRecoveryJournal).toHaveBeenCalledWith(
      { operation: 'restore', operationId: 'restore-id' },
      expect.any(Function),
    );
    expect(jest.mocked(fixture.database.withRecoveryJournal).mock.invocationCallOrder[0])
      .toBeLessThan(fixture.fileSystem.move.mock.invocationCallOrder[0] ?? Number.MAX_SAFE_INTEGER);
  });

  test('syncs every restore payload and the candidate media directory before replacement', async () => {
    const fixture = createFixture();

    await fixture.service.restore('file:///picker/valid.zip');

    const mediaCandidate = 'file:///documents/media.restore-restore-id';
    const databaseCandidate = '/sqlite/app.db.restore-restore-id';
    expect(fixture.fileSystem.syncFile).toHaveBeenCalledWith(`${mediaCandidate}/photo.jpg`);
    expect(fixture.fileSystem.syncDirectory).toHaveBeenCalledWith(mediaCandidate);
    expect(fixture.fileSystem.syncFile).toHaveBeenCalledWith(databaseCandidate);

    const firstMove = fixture.fileSystem.move.mock.invocationCallOrder[0];
    const databaseSyncIndex = fixture.fileSystem.syncFile.mock.calls
      .findIndex(([path]) => path === databaseCandidate);
    const mediaSyncIndex = fixture.fileSystem.syncFile.mock.calls
      .findIndex(([path]) => path === `${mediaCandidate}/photo.jpg`);
    expect(fixture.fileSystem.syncFile.mock.invocationCallOrder[databaseSyncIndex])
      .toBeLessThan(firstMove);
    expect(fixture.fileSystem.syncFile.mock.invocationCallOrder[mediaSyncIndex])
      .toBeLessThan(fixture.fileSystem.syncDirectory.mock.invocationCallOrder[0]);
    expect(fixture.fileSystem.syncDirectory.mock.invocationCallOrder[0]).toBeLessThan(firstMove);
  });

  test('aborts before arming recovery if a copied media payload cannot be synced', async () => {
    const fixture = createFixture();
    const syncError = new Error('media fsync failed');
    fixture.fileSystem.failSync(
      'file:///documents/media.restore-restore-id/photo.jpg',
      syncError,
    );

    await expect(fixture.service.restore('file:///picker/valid.zip')).rejects.toThrow(syncError);

    expect(fixture.database.withRecoveryJournal).not.toHaveBeenCalled();
    await expect(fixture.fileSystem.readBytes('/sqlite/app.db')).resolves.toEqual(OLD_DATABASE);
    await expect(fixture.fileSystem.readBytes('file:///documents/media/old.jpg'))
      .resolves.toEqual(bytes('old photo'));
  });

  test('holds root maintenance through cleanup and durably publishes its warning', async () => {
    const fixture = createFixture();
    const operationDirectory = 'file:///cache/backup-work/restore-id';
    let activeDuringCleanup = false;
    fixture.fileSystem.observeDelete(operationDirectory, () => {
      activeDuringCleanup = fixture.maintenance.getSnapshot().active;
    });
    fixture.fileSystem.failDelete(operationDirectory, new Error('restore temp is locked'));

    const result = await fixture.service.restore('file:///picker/valid.zip');

    expect(activeDuringCleanup).toBe(true);
    expect(result).toMatchObject({
      status: 'restored',
      cleanupWarning: expect.stringContaining('restore temp is locked'),
    });
    expect(fixture.maintenance.getSnapshot()).toMatchObject({
      active: false,
      operation: null,
      warning: expect.stringContaining('restore temp is locked'),
    });
  });

  test('retires successful restore rollback artifacts before the recovery journal can clear', async () => {
    const fixture = createFixture();
    fixture.fileSystem.seedFile('/sqlite/app.db-wal', bytes('old wal'));
    fixture.fileSystem.seedFile('/sqlite/app.db-shm', bytes('old shm'));

    await fixture.service.restore('file:///picker/valid.zip');

    const journalCleared = fixture.events.indexOf('journal-cleared');
    expect(journalCleared).toBeGreaterThan(-1);
    for (const rollbackPath of [
      '/sqlite/app.db.rollback-restore-id',
      '/sqlite/app.db-wal.rollback-restore-id',
      '/sqlite/app.db-shm.rollback-restore-id',
      'file:///documents/media.rollback-restore-id',
    ]) {
      expect(fixture.fileSystem.exists(rollbackPath)).toBe(false);
      expect(fixture.events.indexOf(`delete:${rollbackPath}`)).toBeGreaterThan(-1);
      expect(fixture.events.indexOf(`delete:${rollbackPath}`)).toBeLessThan(journalCleared);
    }
  });

  test('keeps recovery armed and closes the restored handle when rollback retirement fails', async () => {
    const fixture = createFixture();
    const retirementError = new Error('restored rollback database is locked');
    fixture.fileSystem.failDelete('/sqlite/app.db.rollback-restore-id', retirementError);

    await expect(fixture.service.restore('file:///picker/valid.zip')).rejects.toMatchObject({
      name: 'DatabaseRecoveryRequiredError',
    });

    expect(fixture.database.markRecoveryRequired).toHaveBeenCalledWith(expect.objectContaining({
      errors: expect.arrayContaining([retirementError]),
    }));
    expect(fixture.events).not.toContain('journal-cleared');
    expect(fixture.events.indexOf('database-close-reopened')).toBeGreaterThan(-1);
    expect(fixture.events.indexOf('database-close-reopened')).toBeLessThan(
      fixture.events.indexOf('recovery-required'),
    );
    expect(fixture.fileSystem.exists('/sqlite/app.db.rollback-restore-id')).toBe(true);
  });

  test('removes a registered media candidate when copying its first payload fails', async () => {
    const fixture = createFixture();
    fixture.fileSystem.failCopyTo(
      'file:///documents/media.restore-restore-id/photo.jpg',
      new Error('media copy failed'),
    );

    await expect(fixture.service.restore('file:///picker/valid.zip')).rejects.toThrow(
      'media copy failed',
    );

    expect(fixture.fileSystem.exists('file:///documents/media.restore-restore-id')).toBe(false);
    expect(fixture.database.withClosedDatabase).not.toHaveBeenCalled();
  });

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
      name: 'DatabaseRecoveryRequiredError',
    });
    expect(fixture.database.markRecoveryRequired).toHaveBeenCalledWith(expect.objectContaining({
      name: 'AggregateError',
      errors: expect.arrayContaining([
        expect.objectContaining({ message: 'install media failed' }),
        expect.objectContaining({ message: 'database rollback failed' }),
      ]),
    }));
    expect(fixture.events).not.toContain('database-reopen');
    expect(fixture.database.reopen).not.toHaveBeenCalled();
  });

  test('removes candidate sidecars and restores old sidecars before reopening after a failed candidate open', async () => {
    const fixture = createFixture({
      automaticReopenFailure: new Error('restored database failed to open'),
      createCandidateSidecars: true,
    });
    fixture.fileSystem.seedFile('/sqlite/app.db-wal', bytes('old wal'));
    fixture.fileSystem.seedFile('/sqlite/app.db-shm', bytes('old shm'));

    await expect(fixture.service.restore('file:///picker/valid.zip')).rejects.toThrow(
      'restored database failed to open',
    );

    await expect(fixture.fileSystem.readBytes('/sqlite/app.db')).resolves.toEqual(OLD_DATABASE);
    await expect(fixture.fileSystem.readBytes('/sqlite/app.db-wal')).resolves.toEqual(bytes('old wal'));
    await expect(fixture.fileSystem.readBytes('/sqlite/app.db-shm')).resolves.toEqual(bytes('old shm'));
    expect(fixture.events).toContain('journal-cleared');
  });

  test('removes candidate sidecars when the old database had no sidecars before reopening', async () => {
    const fixture = createFixture({
      automaticReopenFailure: new Error('restored database failed to open'),
      createCandidateSidecars: true,
    });

    await expect(fixture.service.restore('file:///picker/valid.zip')).rejects.toThrow(
      'restored database failed to open',
    );

    await expect(fixture.fileSystem.readBytes('/sqlite/app.db')).resolves.toEqual(OLD_DATABASE);
    expect(fixture.fileSystem.exists('/sqlite/app.db-wal')).toBe(false);
    expect(fixture.fileSystem.exists('/sqlite/app.db-shm')).toBe(false);
    expect(fixture.events).toContain('journal-cleared');
  });

  test('keeps the database closed when a retired old sidecar rollback copy is missing', async () => {
    const fixture = createFixture({
      automaticReopenFailure: new Error('restored database failed to open'),
      createCandidateSidecars: true,
      dropWalRollbackBeforeFailure: true,
    });
    fixture.fileSystem.seedFile('/sqlite/app.db-wal', bytes('old wal'));
    fixture.fileSystem.seedFile('/sqlite/app.db-shm', bytes('old shm'));

    await expect(fixture.service.restore('file:///picker/valid.zip')).rejects.toMatchObject({
      name: 'DatabaseRecoveryRequiredError',
    });

    expect(fixture.database.markRecoveryRequired).toHaveBeenCalled();
    expect(fixture.database.reopen).not.toHaveBeenCalled();
    expect(fixture.fileSystem.exists('/sqlite/app.db-wal')).toBe(false);
  });
});

describe('BackupService clear', () => {
  test('owns the global maintenance lease through whole-media retirement', async () => {
    const fixture = createFixture();
    let activeDuringRetirement = false;
    fixture.fileSystem.observeDelete(
      'file:///documents/media.rollback-clear-restore-id',
      () => {
        activeDuringRetirement = fixture.maintenance.getSnapshot().active;
      },
    );

    const result = await fixture.service.clear();

    expect(activeDuringRetirement).toBe(true);
    expect(result).toEqual({ cleanupPending: false });
    expect(fixture.maintenance.getSnapshot()).toMatchObject({
      active: false,
      operation: null,
      warning: null,
    });
  });

  test('pre-arms recovery and atomically swaps the whole media directory before publishing', async () => {
    const fixture = createFixture();

    await fixture.service.clear();

    expect(fixture.database.withRecoveryJournal).toHaveBeenCalledWith(
      { operation: 'clear', operationId: 'restore-id' },
      expect.any(Function),
    );
    expect(jest.mocked(fixture.database.withRecoveryJournal).mock.invocationCallOrder[0])
      .toBeLessThan(fixture.fileSystem.move.mock.invocationCallOrder[0] ?? Number.MAX_SAFE_INTEGER);
    expect(fixture.fileSystem.move).toHaveBeenCalledWith(
      'file:///documents/media',
      'file:///documents/media.rollback-clear-restore-id',
    );
    expect(fixture.fileSystem.ensureDirectory).toHaveBeenCalledWith('file:///documents/media');
    expect(fixture.media.remove).not.toHaveBeenCalled();
    expect(fixture.media.removeOrphans).not.toHaveBeenCalled();
    expect(fixture.events.indexOf('delete:file:///documents/media.rollback-clear-restore-id'))
      .toBeLessThan(fixture.events.indexOf('journal-cleared'));
    expect(fixture.fileSystem.list('file:///documents/media')).toEqual([]);
  });

  test('retires the old database file set before the recovery journal can clear', async () => {
    const fixture = createFixture();
    fixture.fileSystem.seedFile('/sqlite/app.db-wal', bytes('old wal'));
    fixture.fileSystem.seedFile('/sqlite/app.db-shm', bytes('old shm'));

    await fixture.service.clear();

    const journalCleared = fixture.events.indexOf('journal-cleared');
    expect(journalCleared).toBeGreaterThan(-1);
    for (const rollbackPath of [
      '/sqlite/app.db.rollback-clear-restore-id',
      '/sqlite/app.db-wal.rollback-clear-restore-id',
      '/sqlite/app.db-shm.rollback-clear-restore-id',
    ]) {
      expect(fixture.fileSystem.exists(rollbackPath)).toBe(false);
      expect(fixture.events.indexOf(`delete:${rollbackPath}`)).toBeGreaterThan(-1);
      expect(fixture.events.indexOf(`delete:${rollbackPath}`)).toBeLessThan(journalCleared);
    }
  });

  test('keeps recovery armed and closes the empty handle when old-database retirement fails', async () => {
    const fixture = createFixture();
    const retirementError = new Error('old database rollback is locked');
    fixture.fileSystem.failDelete(
      '/sqlite/app.db.rollback-clear-restore-id',
      retirementError,
    );

    await expect(fixture.service.clear()).rejects.toMatchObject({
      name: 'DatabaseRecoveryRequiredError',
    });

    expect(fixture.database.markRecoveryRequired).toHaveBeenCalledWith(expect.objectContaining({
      errors: expect.arrayContaining([retirementError]),
    }));
    expect(fixture.events).not.toContain('journal-cleared');
    expect(fixture.events.indexOf('database-close-reopened')).toBeGreaterThan(-1);
    expect(fixture.events.indexOf('database-close-reopened')).toBeLessThan(
      fixture.events.indexOf('recovery-required'),
    );
    expect(fixture.fileSystem.exists('/sqlite/app.db.rollback-clear-restore-id')).toBe(true);
  });

  test('fails closed when old-database retirement cannot determine whether an artifact exists', async () => {
    const fixture = createFixture();
    const inspectionError = new Error('rollback directory became unreadable');
    fixture.fileSystem.failExists(
      '/sqlite/app.db.rollback-clear-restore-id',
      inspectionError,
    );

    await expect(fixture.service.clear()).rejects.toMatchObject({
      name: 'DatabaseRecoveryRequiredError',
    });

    expect(fixture.database.markRecoveryRequired).toHaveBeenCalledWith(expect.objectContaining({
      errors: expect.arrayContaining([inspectionError]),
    }));
    expect(fixture.events).toContain('database-close-reopened');
    expect(fixture.events).not.toContain('journal-cleared');
  });

  test('keeps recovery armed and closes the empty handle if old media cannot be retired', async () => {
    const fixture = createFixture();
    const retirementError = new Error('old media directory is locked');
    fixture.fileSystem.failDelete(
      'file:///documents/media.rollback-clear-restore-id',
      retirementError,
    );

    await expect(fixture.service.clear()).rejects.toMatchObject({
      name: 'DatabaseRecoveryRequiredError',
    });

    expect(fixture.database.markRecoveryRequired).toHaveBeenCalledWith(expect.objectContaining({
      errors: expect.arrayContaining([retirementError]),
    }));
    expect(fixture.events).toContain('database-close-reopened');
    expect(fixture.events).not.toContain('journal-cleared');
    expect(fixture.fileSystem.exists('file:///documents/media.rollback-clear-restore-id')).toBe(true);
  });

  test('does not follow a stale external reference while clearing the private media root', async () => {
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
    expect(fixture.media.remove).not.toHaveBeenCalled();
    expect(fixture.media.removeOrphans).not.toHaveBeenCalled();
  });

  test('removes sidecars created by a failed empty-database open before restoring and reopening', async () => {
    const fixture = createFixture({
      automaticReopenFailure: new Error('empty database failed to open'),
      createCandidateSidecars: true,
    });

    await expect(fixture.service.clear()).rejects.toThrow('empty database failed to open');

    await expect(fixture.fileSystem.readBytes('/sqlite/app.db')).resolves.toEqual(OLD_DATABASE);
    await expect(fixture.fileSystem.readBytes('file:///documents/media/old.jpg'))
      .resolves.toEqual(bytes('old photo'));
    expect(fixture.fileSystem.exists('file:///documents/media.rollback-clear-restore-id')).toBe(false);
    expect(fixture.fileSystem.exists('/sqlite/app.db-wal')).toBe(false);
    expect(fixture.fileSystem.exists('/sqlite/app.db-shm')).toBe(false);
    expect(fixture.events).toContain('journal-cleared');
  });

  test('keeps the database closed when clear rollback cannot restore a complete file set', async () => {
    const fixture = createFixture({
      automaticReopenFailure: new Error('empty database failed to open'),
      createCandidateSidecars: true,
    });
    fixture.fileSystem.failMoveFromMatching(
      /app\.db\.rollback-clear-restore-id$/,
      new Error('old database restore failed'),
    );

    await expect(fixture.service.clear()).rejects.toMatchObject({
      name: 'DatabaseRecoveryRequiredError',
    });
    expect(fixture.database.markRecoveryRequired).toHaveBeenCalled();
    expect(fixture.database.reopen).not.toHaveBeenCalled();
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

test('SHA-256 hashes a large payload incrementally with bounded reads', async () => {
  const payloadSize = 2 * 1024 * 1024 + 17;
  const readLengths: number[] = [];
  const fullRead = jest.fn(async () => {
    throw new Error('whole-file read is forbidden');
  });
  const reader: BackupFileReader = {
    size: payloadSize,
    read: jest.fn(async (_offset, length) => {
      readLengths.push(length);
      return new Uint8Array(length).fill(0x61);
    }),
    close: jest.fn(async () => undefined),
  };
  const fileSystem = {
    openRead: jest.fn(async () => reader),
    readBytes: fullRead,
  } as unknown as BackupFileSystem;

  await expect(sha256File('file:///large-video.mp4', fileSystem)).resolves.toBe(
    'c2273a45bd6d19d2714b8279b1fd1123bb746e7f7f6331085fb6ecaa30164546',
  );

  expect(Math.max(...readLengths)).toBeLessThan(payloadSize);
  expect(readLengths.reduce((total, length) => total + length, 0)).toBe(payloadSize);
  expect(fullRead).not.toHaveBeenCalled();
  expect(reader.close).toHaveBeenCalledTimes(1);
});

type FixtureOptions = {
  automaticReopenFailure?: Error;
  createCandidateSidecars?: boolean;
  dropWalRollbackBeforeFailure?: boolean;
  manifestVersion?: number;
  mediaHash?: string;
  mediaSize?: number;
};

function createFixture(options: FixtureOptions = {}) {
  const events: string[] = [];
  const maintenance = createMaintenanceCoordinator();
  const fileSystem = new MemoryBackupFileSystem(events);
  fileSystem.seedFile('/sqlite/app.db', OLD_DATABASE);
  fileSystem.seedFile('file:///documents/media/old.jpg', bytes('old photo'));
  fileSystem.seedFile('file:///documents/media/photo.jpg', PHOTO);
  const markRecoveryRequired = jest.fn((cause: unknown) => {
    events.push('recovery-required');
    return new DatabaseRecoveryRequiredError(
      'Local data recovery is required before the database can be reopened.',
      cause,
    );
  });
  const withClosedDatabase = jest.fn(async (work: (databasePath: string) => Promise<unknown>) => {
    events.push('database-close-current');
    try {
      const result = await work('/sqlite/app.db');
      if (options.automaticReopenFailure !== undefined) {
        events.push('database-reopen-failed');
        if (options.dropWalRollbackBeforeFailure === true) {
          fileSystem.deleteNow('/sqlite/app.db-wal.rollback-restore-id');
        }
        if (options.createCandidateSidecars === true) {
          fileSystem.seedFile('/sqlite/app.db-wal', bytes('candidate wal'));
          fileSystem.seedFile('/sqlite/app.db-shm', bytes('candidate shm'));
        }
        throw options.automaticReopenFailure;
      }
      events.push('database-reopen');
      return result;
    } catch (cause) {
      if (!(cause instanceof DatabaseRecoveryRequiredError) &&
          cause !== options.automaticReopenFailure) {
        events.push('database-reopen');
      }
      throw cause;
    }
  });
  const withRecoveryJournal = jest.fn(async (
    _journal: { operation: 'restore' | 'clear' | 'manual'; operationId: string },
    work: (context: {
      databasePath: string;
      reopen(): Promise<SQLiteDatabase>;
      closeReopened(): Promise<void>;
    }) => Promise<unknown>,
  ) => {
    events.push('journal-armed');
    events.push('database-close-current');
    let reopenAttempts = 0;
    let safelyReopened = false;
    const reopen = async () => {
      reopenAttempts += 1;
      if (reopenAttempts === 1 && options.automaticReopenFailure !== undefined) {
        events.push('database-reopen-failed');
        if (options.dropWalRollbackBeforeFailure === true) {
          fileSystem.deleteNow('/sqlite/app.db-wal.rollback-restore-id');
        }
        if (options.createCandidateSidecars === true) {
          fileSystem.seedFile('/sqlite/app.db-wal', bytes('candidate wal'));
          fileSystem.seedFile('/sqlite/app.db-shm', bytes('candidate shm'));
        }
        throw options.automaticReopenFailure;
      }
      safelyReopened = true;
      events.push('database-reopen');
      return {} as SQLiteDatabase;
    };
    const closeReopened = async () => {
      safelyReopened = false;
      events.push('database-close-reopened');
    };
    try {
      const result = await work({ closeReopened, databasePath: '/sqlite/app.db', reopen });
      if (!safelyReopened) {
        throw new Error('Recovery work did not safely reopen the database.');
      }
      events.push('journal-cleared');
      return result;
    } catch (cause) {
      if (safelyReopened) {
        events.push('journal-cleared');
      }
      throw cause;
    }
  });
  const database: DatabaseManager = {
    initialize: jest.fn(),
    reopen: jest.fn(async () => {
      events.push('database-reopen');
      return {} as never;
    }),
    withClosedDatabase: withClosedDatabase as DatabaseManager['withClosedDatabase'],
    withRecoveryJournal: withRecoveryJournal as DatabaseManager['withRecoveryJournal'],
    markRecoveryRequired,
    getLifecycleSnapshot: jest.fn(() => ({ status: 'closed' })),
    subscribe: jest.fn(() => () => undefined),
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
    listPage: jest.fn(async () => ({ records: [], nextCursor: null })),
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
    remove: jest.fn<Promise<void>, [string[]]>(async () => {
      events.push('media-remove');
    }),
    removeOrphans: jest.fn<Promise<void>, [string[]]>(async () => {
      events.push('orphan-cleanup');
    }),
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
  const readSnapshotMediaPaths = jest.fn(async () => [
    'file:///documents/media/photo.jpg',
  ]);
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
    maintenance,
    now: () => new Date('2026-08-01T12:00:00.000Z'),
    pickArchive: jest.fn(async () => 'file:///picker/valid.zip'),
    records,
    readSnapshotMediaPaths,
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
    maintenance,
    records,
    readSnapshotMediaPaths,
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
  private readonly copyToFailures = new Map<string, Error>();
  private readonly deleteFailures = new Map<string, Error>();
  private readonly deleteObservers = new Map<string, () => void>();
  private readonly existsFailures = new Map<string, Error>();
  private readonly syncFailures = new Map<string, Error>();
  private readonly moveFromFailures: Array<{ pattern: RegExp; error: Error }> = [];

  constructor(private readonly events: string[] = []) {}

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

  failCopyTo(path: string, error: Error): void {
    this.copyToFailures.set(path, error);
  }

  failDelete(path: string, error: Error): void {
    this.deleteFailures.set(path, error);
  }

  failExists(path: string, error: Error): void {
    this.existsFailures.set(path, error);
  }

  failSync(path: string, error: Error): void {
    this.syncFailures.set(path, error);
  }

  observeDelete(path: string, observer: () => void): void {
    this.deleteObservers.set(path, observer);
  }

  failMoveFromMatching(pattern: RegExp, error: Error): void {
    this.moveFromFailures.push({ pattern, error });
  }

  exists = jest.fn((path: string) => {
    const failure = this.existsFailures.get(path);
    if (failure !== undefined) {
      this.existsFailures.delete(path);
      throw failure;
    }
    return this.files.has(path) || this.directories.has(path);
  });
  size = jest.fn((path: string) => this.files.get(path)?.length ?? 0);
  openRead = jest.fn(async (path: string): Promise<BackupFileReader> => {
    const value = this.files.get(path);
    if (value === undefined) {
      throw new Error(`Missing file: ${path}`);
    }
    return memoryReader(value);
  });
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
  syncFile = jest.fn(async (path: string) => {
    this.events.push(`sync-file:${path}`);
    const failure = this.syncFailures.get(path);
    if (failure !== undefined) {
      this.syncFailures.delete(path);
      throw failure;
    }
    if (!this.files.has(path)) {
      throw new Error(`Missing file: ${path}`);
    }
  });
  syncDirectory = jest.fn(async (path: string) => {
    this.events.push(`sync-directory:${path}`);
    const failure = this.syncFailures.get(path);
    if (failure !== undefined) {
      this.syncFailures.delete(path);
      throw failure;
    }
    if (!this.directories.has(path)) {
      throw new Error(`Missing directory: ${path}`);
    }
  });
  copyFile = jest.fn(async (source: string, target: string) => {
    const value = await this.readBytes(source);
    const failure = this.copyToFailures.get(target);
    if (failure !== undefined) {
      this.copyToFailures.delete(target);
      this.seedFile(target, value.subarray(0, Math.max(1, Math.floor(value.length / 2))));
      throw failure;
    }
    this.seedFile(target, value);
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
    this.events.push(`delete:${path}`);
    this.deleteObservers.get(path)?.();
    const failure = this.deleteFailures.get(path);
    if (failure !== undefined) {
      this.deleteFailures.delete(path);
      throw failure;
    }
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

type ZipFixtureEntry = {
  centralPath: string;
  localPath: string;
  centralFlags?: number;
  localFlags?: number;
  centralMethod?: number;
  localMethod?: number;
  centralCrc?: number;
  localCrc?: number;
  centralCompressedSize?: number;
  localCompressedSize?: number;
  centralUncompressedSize?: number;
  localUncompressedSize?: number;
  centralExtra?: number[];
  localExtra?: number[];
  data?: number[];
};

function zipFixture(entries: ZipFixtureEntry[]): Uint8Array {
  const chunks: number[] = [];
  const central: number[] = [];
  const offsets: number[] = [];
  for (const entry of entries) {
    offsets.push(chunks.length);
    const name = [...bytes(entry.localPath)];
    const extra = entry.localExtra ?? [];
    pushU32(chunks, 0x04034b50);
    pushU16(chunks, 20);
    pushU16(chunks, entry.localFlags ?? 0x0800);
    pushU16(chunks, entry.localMethod ?? 0);
    pushU16(chunks, 0);
    pushU16(chunks, 0);
    pushU32(chunks, entry.localCrc ?? 0);
    pushU32(chunks, entry.localCompressedSize ?? 0);
    pushU32(chunks, entry.localUncompressedSize ?? 0);
    pushU16(chunks, name.length);
    pushU16(chunks, extra.length);
    chunks.push(...name);
    chunks.push(...extra);
    chunks.push(...(entry.data ?? []));
  }
  const centralOffset = chunks.length;
  entries.forEach((entry, index) => {
    const name = [...bytes(entry.centralPath)];
    const extra = entry.centralExtra ?? [];
    pushU32(central, 0x02014b50);
    pushU16(central, 20);
    pushU16(central, 20);
    pushU16(central, entry.centralFlags ?? 0x0800);
    pushU16(central, entry.centralMethod ?? 0);
    pushU16(central, 0);
    pushU16(central, 0);
    pushU32(central, entry.centralCrc ?? 0);
    pushU32(central, entry.centralCompressedSize ?? 0);
    pushU32(central, entry.centralUncompressedSize ?? 0);
    pushU16(central, name.length);
    pushU16(central, extra.length);
    pushU16(central, 0);
    pushU16(central, 0);
    pushU16(central, 0);
    pushU32(central, 0);
    pushU32(central, offsets[index]);
    central.push(...name);
    central.push(...extra);
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

function memoryReader(value: Uint8Array, readLengths: number[] = []): BackupFileReader {
  return {
    size: value.length,
    async read(offset, length) {
      readLengths.push(length);
      return value.slice(offset, offset + length);
    },
    async close() {},
  };
}

function sparseZipReader(centralOffset: number): {
  reader: BackupFileReader;
  readLengths: number[];
} {
  const name = [...bytes('manifest.json')];
  const local: number[] = [];
  pushU32(local, 0x04034b50);
  pushU16(local, 20);
  pushU16(local, 0x0800);
  pushU16(local, 0);
  pushU16(local, 0);
  pushU16(local, 0);
  pushU32(local, 0);
  pushU32(local, centralOffset - 30 - name.length);
  pushU32(local, centralOffset - 30 - name.length);
  pushU16(local, name.length);
  pushU16(local, 0);
  local.push(...name);

  const central: number[] = [];
  pushU32(central, 0x02014b50);
  pushU16(central, 20);
  pushU16(central, 20);
  pushU16(central, 0x0800);
  pushU16(central, 0);
  pushU16(central, 0);
  pushU16(central, 0);
  pushU32(central, 0);
  pushU32(central, centralOffset - local.length);
  pushU32(central, centralOffset - local.length);
  pushU16(central, name.length);
  pushU16(central, 0);
  pushU16(central, 0);
  pushU16(central, 0);
  pushU16(central, 0);
  pushU32(central, 0);
  pushU32(central, 0);
  central.push(...name);

  const eocd: number[] = [];
  pushU32(eocd, 0x06054b50);
  pushU16(eocd, 0);
  pushU16(eocd, 0);
  pushU16(eocd, 1);
  pushU16(eocd, 1);
  pushU32(eocd, central.length);
  pushU32(eocd, centralOffset);
  pushU16(eocd, 0);

  const segments = [
    { offset: 0, bytes: new Uint8Array(local) },
    { offset: centralOffset, bytes: new Uint8Array(central) },
    { offset: centralOffset + central.length, bytes: new Uint8Array(eocd) },
  ];
  const size = centralOffset + central.length + eocd.length;
  const readLengths: number[] = [];
  return {
    readLengths,
    reader: {
      size,
      async read(offset, length) {
        readLengths.push(length);
        const result = new Uint8Array(length);
        for (const segment of segments) {
          const start = Math.max(offset, segment.offset);
          const end = Math.min(offset + length, segment.offset + segment.bytes.length);
          if (start < end) {
            result.set(
              segment.bytes.subarray(start - segment.offset, end - segment.offset),
              start - offset,
            );
          }
        }
        return result;
      },
      async close() {},
    },
  };
}

function pushU16(target: number[], value: number): void {
  target.push(value & 0xff, (value >>> 8) & 0xff);
}

function pushU32(target: number[], value: number): void {
  pushU16(target, value & 0xffff);
  pushU16(target, (value >>> 16) & 0xffff);
}

function pushU64(target: number[], value: number): void {
  pushU32(target, value % 0x1_0000_0000);
  pushU32(target, Math.floor(value / 0x1_0000_0000));
}

function zip64Extra(values: number[]): number[] {
  const data: number[] = [];
  for (const value of values) {
    pushU64(data, value);
  }
  return [0x01, 0x00, data.length & 0xff, data.length >>> 8, ...data];
}
