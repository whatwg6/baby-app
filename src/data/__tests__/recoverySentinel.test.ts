const mockDirectoryList = jest.fn();
const mockSentinelCreate = jest.fn();
const mockSentinelWrite = jest.fn();
const mockSentinel = {
  create: mockSentinelCreate,
  exists: false,
  write: mockSentinelWrite,
};

jest.mock('expo-file-system', () => ({
  Directory: jest.fn(() => ({ list: mockDirectoryList })),
  File: jest.fn(() => mockSentinel),
  Paths: { document: { uri: 'file:///documents' } },
}));

import { Directory, File } from 'expo-file-system';

import { createExpoRecoverySentinelStore } from '../recoverySentinel';

const SENTINEL_NAME = 'baby-growth-recovery-required.json';

beforeEach(() => {
  mockDirectoryList.mockReset();
  mockDirectoryList.mockReturnValue([]);
  mockSentinelCreate.mockReset();
  mockSentinelWrite.mockReset();
  jest.mocked(Directory).mockClear();
  jest.mocked(File).mockClear();
});

test('reports absence only after successfully listing Documents without the sentinel', () => {
  const store = createExpoRecoverySentinelStore('file:///private-documents');

  expect(store.isRecoveryRequired()).toBe(false);

  expect(Directory).toHaveBeenCalledWith('file:///private-documents');
  expect(mockDirectoryList).toHaveBeenCalledTimes(1);
});

test('reports recovery-required when the sentinel name is listed', () => {
  mockDirectoryList.mockReturnValue([{ name: SENTINEL_NAME }]);
  const store = createExpoRecoverySentinelStore();

  expect(store.isRecoveryRequired()).toBe(true);
});

test('throws when Documents cannot be listed so the database fails closed', () => {
  const permissionError = new Error('Documents read permission denied');
  mockDirectoryList.mockImplementation(() => {
    throw permissionError;
  });
  const store = createExpoRecoverySentinelStore();

  expect(() => store.isRecoveryRequired()).toThrow(permissionError);
});

test('propagates a sentinel write failure', () => {
  const writeError = new Error('sentinel write denied');
  mockSentinelWrite.mockImplementation(() => {
    throw writeError;
  });
  const store = createExpoRecoverySentinelStore();

  expect(() => store.markRecoveryRequired()).toThrow(writeError);
  expect(mockSentinelCreate).toHaveBeenCalledWith({ overwrite: true });
});

test('a listed unreadable partial sentinel still blocks recovery', () => {
  mockDirectoryList.mockReturnValue([{ name: SENTINEL_NAME }]);
  mockSentinel.exists = false;
  const store = createExpoRecoverySentinelStore();

  expect(store.isRecoveryRequired()).toBe(true);
});
