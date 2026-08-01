const mockDirectoryList = jest.fn();
const mockSentinelCreate = jest.fn();
const mockSentinelWrite = jest.fn();
const mockSentinelDelete = jest.fn();
const mockJournalExecSync = jest.fn();
const mockJournalGetFirstSync = jest.fn();
const mockJournalRunSync = jest.fn();
const mockJournalWithTransactionSync = jest.fn();
const mockOpenDatabaseSync = jest.fn();
type JournalRow = { operation: string; operationId: string };
const journalRows = new Map<string, JournalRow | null>();
const journalDatabases = new Map<string, {
  execSync: typeof mockJournalExecSync;
  getFirstSync(source: string): JournalRow | null;
  runSync(source: string, ...parameters: string[]): { changes: number; lastInsertRowId: number };
  withTransactionSync(work: () => void): void;
}>();
const mockSentinel = {
  create: mockSentinelCreate,
  delete: mockSentinelDelete,
  exists: false,
  write: mockSentinelWrite,
};

jest.mock('expo-file-system', () => ({
  Directory: jest.fn(() => ({ list: mockDirectoryList })),
  File: jest.fn(() => mockSentinel),
  Paths: { document: { uri: 'file:///documents' } },
}));
jest.mock('expo-sqlite', () => ({
  defaultDatabaseDirectory: 'file:///sqlite',
  openDatabaseSync: mockOpenDatabaseSync,
}));

import { Directory, File } from 'expo-file-system';

import { createExpoRecoverySentinelStore } from '../recoverySentinel';

const SENTINEL_NAME = 'baby-growth-recovery-required.json';

beforeEach(() => {
  mockDirectoryList.mockReset();
  mockDirectoryList.mockReturnValue([]);
  mockSentinelCreate.mockReset();
  mockSentinelWrite.mockReset();
  mockSentinelDelete.mockReset();
  mockSentinel.exists = false;
  journalRows.clear();
  journalDatabases.clear();
  mockJournalExecSync.mockReset();
  mockJournalGetFirstSync.mockReset();
  mockJournalGetFirstSync.mockImplementation((directory: string) => (
    journalRows.get(directory) ?? null
  ));
  mockJournalRunSync.mockReset();
  mockJournalRunSync.mockImplementation((
    directory: string,
    source: string,
    ...parameters: string[]
  ) => {
    const statement = source.trimStart();
    if (statement.startsWith('INSERT')) {
      journalRows.set(directory, { operation: parameters[0], operationId: parameters[1] });
      return { changes: 1, lastInsertRowId: 1 };
    }
    if (statement.startsWith('DELETE')) {
      const changes = journalRows.get(directory) == null ? 0 : 1;
      journalRows.set(directory, null);
      return { changes, lastInsertRowId: 0 };
    }
    throw new Error(`Unexpected recovery-journal SQL: ${source}`);
  });
  mockJournalWithTransactionSync.mockReset();
  mockJournalWithTransactionSync.mockImplementation((work: () => void) => work());
  mockOpenDatabaseSync.mockReset();
  mockOpenDatabaseSync.mockImplementation((directory: string) => {
    const existing = journalDatabases.get(directory);
    if (existing !== undefined) {
      return existing;
    }
    const database = {
      execSync: mockJournalExecSync,
      getFirstSync: (source: string) => mockJournalGetFirstSync(directory, source),
      runSync: (source: string, ...parameters: string[]) => (
        mockJournalRunSync(directory, source, ...parameters)
      ),
      withTransactionSync: (work: () => void) => mockJournalWithTransactionSync(work),
    };
    journalDatabases.set(directory, database);
    return database;
  });
  jest.mocked(Directory).mockClear();
  jest.mocked(File).mockClear();
});

test('reports absence only after successfully listing Documents without the sentinel', () => {
  const store = createStore('file:///private-documents');

  expect(store.isRecoveryRequired()).toBe(false);

  expect(Directory).toHaveBeenCalledWith('file:///private-documents');
  expect(mockDirectoryList).toHaveBeenCalledTimes(1);
});

test('reports recovery-required when the sentinel name is listed', () => {
  mockDirectoryList.mockReturnValue([{ name: SENTINEL_NAME }]);
  const store = createStore();

  expect(store.isRecoveryRequired()).toBe(true);
});

test('throws when Documents cannot be listed so the database fails closed', () => {
  const permissionError = new Error('Documents read permission denied');
  mockDirectoryList.mockImplementation(() => {
    throw permissionError;
  });
  const store = createStore();

  expect(() => store.isRecoveryRequired()).toThrow(permissionError);
});

test('propagates a durable journal transaction failure before legacy-file writes', () => {
  const writeError = new Error('journal commit denied');
  mockJournalWithTransactionSync.mockImplementation(() => {
    throw writeError;
  });
  const store = createStore();

  expect(() => store.markRecoveryRequired()).toThrow(writeError);
  expect(mockSentinelCreate).not.toHaveBeenCalled();
});

test('a listed unreadable partial sentinel still blocks recovery', () => {
  mockDirectoryList.mockReturnValue([{ name: SENTINEL_NAME }]);
  mockSentinel.exists = false;
  const store = createStore();

  expect(store.isRecoveryRequired()).toBe(true);
});

test('persists recovery metadata in a fully synchronous SQLite transaction before returning', () => {
  mockDirectoryList
    .mockReturnValueOnce([{ name: SENTINEL_NAME }])
    .mockReturnValue([]);
  const store = createStore();

  store.markRecoveryRequired({ operation: 'restore', operationId: 'restore-42' });

  expect(mockJournalExecSync).toHaveBeenCalledWith(expect.stringMatching(
    /journal_mode\s*=\s*DELETE[\s\S]*synchronous\s*=\s*EXTRA[\s\S]*fullfsync\s*=\s*ON/i,
  ));
  expect(journalRows.get('file:///sqlite')).toEqual({
    operation: 'restore',
    operationId: 'restore-42',
  });
  expect(journalRows.get('file:///documents')).toEqual({
    operation: 'restore',
    operationId: 'restore-42',
  });
  expect(mockJournalWithTransactionSync).toHaveBeenCalledTimes(2);

  const restartedStore = createStore();
  expect(restartedStore.isRecoveryRequired()).toBe(true);
});

test('opens durable recovery barriers beside both the primary database and media root', () => {
  const store = createStore('file:///documents');

  expect(store.isRecoveryRequired()).toBe(false);

  expect(mockOpenDatabaseSync.mock.calls.map(([directory]) => directory)).toEqual([
    'file:///sqlite',
    'file:///documents',
  ]);
});

test('retains the primary barrier if arming the media barrier fails', () => {
  const mediaBarrierError = new Error('media barrier commit failed');
  mockJournalWithTransactionSync
    .mockImplementationOnce((work: () => void) => work())
    .mockImplementationOnce(() => {
      throw mediaBarrierError;
    });
  const store = createStore();

  expect(() => store.markRecoveryRequired({
    operation: 'clear',
    operationId: 'clear-media-barrier',
  })).toThrow(mediaBarrierError);

  expect(journalRows.get('file:///sqlite')).toEqual({
    operation: 'clear',
    operationId: 'clear-media-barrier',
  });
  expect(journalRows.get('file:///documents') ?? null).toBeNull();
  expect(createStore().isRecoveryRequired()).toBe(true);
});

test('durably clears the media barrier before the primary barrier', () => {
  const store = createStore();
  store.markRecoveryRequired({ operation: 'restore', operationId: 'restore-order' });
  mockJournalRunSync.mockClear();

  store.clearRecoveryRequired();

  const clearedDirectories = mockJournalRunSync.mock.calls
    .filter(([, source]) => String(source).trimStart().startsWith('DELETE'))
    .map(([directory]) => directory);
  expect(clearedDirectories).toEqual(['file:///documents', 'file:///sqlite']);
});

test('clears a completed recovery journal after Documents can be inspected', () => {
  mockSentinel.exists = true;
  mockDirectoryList.mockReturnValue([]);
  const store = createStore();

  store.clearRecoveryRequired();

  expect(mockSentinelDelete).toHaveBeenCalledTimes(1);
  expect(mockDirectoryList).toHaveBeenCalledTimes(1);
});

test('keeps the durable journal when its pre-clear presence cannot be verified', () => {
  const listError = new Error('Documents became unreadable during journal clear');
  let firstRead = true;
  mockSentinel.exists = true;
  mockSentinelDelete.mockImplementation(() => {
    mockSentinel.exists = false;
  });
  mockDirectoryList.mockImplementation(() => {
    if (firstRead) {
      firstRead = false;
      throw listError;
    }
    return mockSentinel.exists ? [{ name: SENTINEL_NAME }] : [];
  });
  const store = createStore();

  expect(() => store.clearRecoveryRequired()).toThrow(listError);
  expect(mockSentinelDelete).not.toHaveBeenCalled();

  const restartedStore = createStore();
  expect(restartedStore.isRecoveryRequired()).toBe(true);
});

function createStore(documentDirectory = 'file:///documents') {
  return createExpoRecoverySentinelStore(documentDirectory, mockOpenDatabaseSync);
}
