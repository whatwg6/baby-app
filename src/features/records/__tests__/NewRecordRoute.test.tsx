import { act, fireEvent, render, waitFor } from '@testing-library/react-native';
import * as ImagePicker from 'expo-image-picker';

import NewRecordRoute from '../../../../app/record/new';
import { AppProvider, type AppServices } from '../../../app/AppProvider';
import type { RecordRepository } from '../../../data/repositories';
import type { BackupService } from '../../backup/backupService';
import type { MediaService, StagedMedia } from '../../media/mediaService';
import { MemoryBabyRepository, MemoryRecordRepository } from '../../../test/memoryRepositories';

const mockPush = jest.fn();
const mockReplace = jest.fn();
let mockTypeParam: string | string[] | undefined;

jest.mock('expo-router', () => ({
  useLocalSearchParams: () => ({ type: mockTypeParam }),
  useRouter: () => ({ push: mockPush, replace: mockReplace }),
}));

jest.mock('expo-image-picker', () => ({
  requestMediaLibraryPermissionsAsync: jest.fn(),
  launchImageLibraryAsync: jest.fn(),
}));

jest.mock('expo-video', () => {
  const { View } = require('react-native') as typeof import('react-native');
  return {
    useVideoPlayer: () => ({ play: jest.fn() }),
    VideoView: (props: Record<string, unknown>) => <View {...props} />,
  };
});

const requestPermission = ImagePicker.requestMediaLibraryPermissionsAsync as jest.MockedFunction<
  typeof ImagePicker.requestMediaLibraryPermissionsAsync
>;
const launchPicker = ImagePicker.launchImageLibraryAsync as jest.MockedFunction<
  typeof ImagePicker.launchImageLibraryAsync
>;

beforeEach(() => {
  jest.clearAllMocks();
  mockTypeParam = undefined;
  requestPermission.mockResolvedValue({
    granted: true,
    canAskAgain: true,
    expires: 'never',
    status: 'granted' as ImagePicker.PermissionStatus,
    accessPrivileges: 'all',
  });
  launchPicker.mockResolvedValue({
    canceled: false,
    assets: [{ uri: 'file:///picker/new-photo.jpg', type: 'image', width: 100, height: 80 }],
  });
});

test('uses the real type picker for absent or invalid queries and routes the selected type', async () => {
  const services = appServices(new MemoryRecordRepository(), mediaDouble());
  const view = await render(routeTree(services));

  expect(view.getByText('选择记录类型')).toBeTruthy();
  await fireEvent.press(view.getByRole('button', { name: /成长数据/ }));
  expect(mockPush).toHaveBeenCalledWith('/record/new?type=growth');

  mockTypeParam = 'unknown-type';
  await view.rerender(routeTree(services));

  expect(view.getByText('选择记录类型')).toBeTruthy();
  expect(view.getByRole('button', { name: /珍贵时刻/ })).toBeTruthy();
});

test('stages and commits picked media through AppServices before navigating with private paths stored', async () => {
  mockTypeParam = 'moment';
  const events: string[] = [];
  const backing = new MemoryRecordRepository();
  const records = observedRepository(backing, events);
  const media = mediaDouble(events);
  mockReplace.mockImplementation(() => {
    events.push('navigate');
  });
  const view = await render(routeTree(appServices(records, media)));

  await fireEvent.press(view.getByRole('button', { name: '选择图片或视频' }));
  await fireEvent.press(view.getByRole('button', { name: '保存' }));

  await waitFor(() => expect(mockReplace).toHaveBeenCalledWith('/(tabs)/timeline'));
  expect(media.stage).toHaveBeenCalledWith({
    uri: 'file:///picker/new-photo.jpg',
    mediaType: 'image',
  });
  expect(media.commit).toHaveBeenCalledTimes(1);
  await expect(backing.list()).resolves.toEqual([
    expect.objectContaining({
      attachments: [expect.objectContaining({
        filePath: 'file:///documents/media/new-photo.jpg',
        thumbnailPath: 'file:///documents/media/new-photo-thumb.jpg',
      })],
    }),
  ]);
  expect(events).toEqual(['stage', 'commit', 'persisted', 'navigate']);
});

test('keeps form and picked-media state after persistence fails without navigating', async () => {
  mockTypeParam = 'moment';
  const media = mediaDouble();
  const backing = new MemoryRecordRepository();
  const records: RecordRepository = {
    create: (input) => backing.create(input),
    update: (id, input) => backing.update(id, input),
    delete: (id) => backing.delete(id),
    get: (id) => backing.get(id),
    list: (filter) => backing.list(filter),
    listPage: (options) => backing.listPage(options),
    withTransaction: async () => {
      throw new Error('database is unavailable');
    },
  };
  const view = await render(routeTree(appServices(records, media)));

  await fireEvent.changeText(view.getByLabelText('备注（可选）'), '保留这段说明');
  await fireEvent.press(view.getByRole('button', { name: '选择图片或视频' }));
  expect(await view.findByLabelText('媒体预览')).toBeTruthy();
  await fireEvent.press(view.getByRole('button', { name: '保存' }));

  expect(await view.findByText('保存失败，已有数据未受影响')).toBeTruthy();
  expect(view.getByLabelText('备注（可选）').props.value).toBe('保留这段说明');
  expect(view.getByLabelText('媒体预览')).toBeTruthy();
  expect(media.rollback).toHaveBeenCalledTimes(1);
  expect(mockReplace).not.toHaveBeenCalled();
});

test('coalesces rapid saves and navigates only after the single persistence attempt completes', async () => {
  mockTypeParam = 'moment';
  const gate = deferred<void>();
  const backing = new MemoryRecordRepository();
  let persistenceAttempts = 0;
  const records: RecordRepository = {
    create: (input) => backing.create(input),
    update: (id, input) => backing.update(id, input),
    delete: (id) => backing.delete(id),
    get: (id) => backing.get(id),
    list: (filter) => backing.list(filter),
    listPage: (options) => backing.listPage(options),
    withTransaction: async (work) => {
      persistenceAttempts += 1;
      await gate.promise;
      return backing.withTransaction(work);
    },
  };
  const view = await render(routeTree(appServices(records, mediaDouble())));
  await fireEvent.changeText(view.getByLabelText('备注（可选）'), '只保存一次');
  const saveButton = view.getByRole('button', { name: '保存' });

  await fireEvent.press(saveButton);
  await fireEvent.press(saveButton);

  expect(persistenceAttempts).toBe(1);
  expect(mockReplace).not.toHaveBeenCalled();

  await act(async () => {
    gate.resolve();
    await gate.promise;
  });

  await waitFor(() => expect(mockReplace).toHaveBeenCalledWith('/(tabs)/timeline'));
  expect(mockReplace).toHaveBeenCalledTimes(1);
  await expect(backing.list()).resolves.toHaveLength(1);
});

function routeTree(services: AppServices) {
  return (
    <AppProvider services={services}>
      <NewRecordRoute />
    </AppProvider>
  );
}

function appServices(records: RecordRepository, media: MediaService): AppServices {
  return {
    babies: new MemoryBabyRepository(),
    records,
    media,
    backup: {
      export: jest.fn(),
      inspect: jest.fn(),
      restore: jest.fn(),
      clear: jest.fn(),
    } as jest.Mocked<BackupService>,
    database: {} as AppServices['database'],
    reportCleanupWarning: jest.fn(),
  };
}

function observedRepository(
  backing: MemoryRecordRepository,
  events: string[],
): RecordRepository {
  return {
    create: (input) => backing.create(input),
    update: (id, input) => backing.update(id, input),
    delete: (id) => backing.delete(id),
    get: (id) => backing.get(id),
    list: (filter) => backing.list(filter),
    listPage: (options) => backing.listPage(options),
    withTransaction: async (work) => {
      const result = await backing.withTransaction(work);
      events.push('persisted');
      return result;
    },
  };
}

function mediaDouble(events?: string[]): jest.Mocked<MediaService> {
  const staged: StagedMedia = {
    stagingPath: 'file:///documents/staging/new-photo.jpg',
    finalPath: 'file:///documents/media/new-photo.jpg',
    mediaType: 'image',
    thumbnailStagingPath: 'file:///documents/staging/new-photo-thumb.jpg',
    thumbnailFinalPath: 'file:///documents/media/new-photo-thumb.jpg',
  };
  return {
    stage: jest.fn(async (_input) => {
      events?.push('stage');
      return staged;
    }),
    commit: jest.fn(async (_staged) => {
      events?.push('commit');
      return {
        filePath: staged.finalPath,
        thumbnailPath: staged.thumbnailFinalPath,
      };
    }),
    rollback: jest.fn(async (_staged) => undefined),
    remove: jest.fn(async (_paths) => undefined),
    removeOrphans: jest.fn(async (_paths) => undefined),
  };
}

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, reject, resolve };
}
