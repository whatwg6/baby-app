import { act, fireEvent, render, waitFor } from '@testing-library/react-native';

import EditRecordRoute from '../../../../app/record/edit/[id]';
import type { RecordRepository, RecordTransaction } from '../../../data/repositories';
import type { NewRecordInput, TimelineRecord } from '../../../domain/types';
import type { MediaService, StagedMedia } from '../../media/mediaService';
import { RecordRepositoryProvider } from '../RecordRepositoryProvider';
import { MemoryRecordRepository } from '../../../test/memoryRepositories';

let mockRouteId = 'first';
const mockReplace = jest.fn();

jest.mock('expo-router', () => ({
  useLocalSearchParams: () => ({ id: mockRouteId }),
  useRouter: () => ({ replace: mockReplace }),
}));

beforeEach(() => {
  mockRouteId = 'first';
  mockReplace.mockReset();
});

test('hides the previous editor immediately when the requested id changes', async () => {
  const first = deferred<TimelineRecord | null>();
  const second = deferred<TimelineRecord | null>();
  const get = jest.fn((id: string) => (id === 'first' ? first.promise : second.promise));
  const view = await renderRoute(createRepository(get));

  await resolve(first, momentRecord('first', '第一条记录'));
  await waitFor(() => expect(view.getByLabelText('备注（可选）').props.value).toBe('第一条记录'));

  mockRouteId = 'second';
  await view.rerender(routeTree(createRepository(get)));

  expect(view.getByText('正在读取记录…')).toBeTruthy();
  expect(view.queryByLabelText('备注（可选）')).toBeNull();
  await resolve(second, momentRecord('second', '第二条记录'));
});

test('ignores an older lookup that resolves after the newer route id', async () => {
  const first = deferred<TimelineRecord | null>();
  const second = deferred<TimelineRecord | null>();
  const get = jest.fn((id: string) => (id === 'first' ? first.promise : second.promise));
  const repository = createRepository(get);
  const view = await renderRoute(repository);

  mockRouteId = 'second';
  await view.rerender(routeTree(repository));
  await waitFor(() => expect(get).toHaveBeenLastCalledWith('second'));

  await resolve(second, momentRecord('second', '第二条记录'));
  await waitFor(() => expect(view.getByLabelText('备注（可选）').props.value).toBe('第二条记录'));
  await resolve(first, momentRecord('first', '第一条记录'));

  await waitFor(() => expect(view.getByLabelText('备注（可选）').props.value).toBe('第二条记录'));
});

test('shows a retryable load error instead of a stale editable record', async () => {
  const first = deferred<TimelineRecord | null>();
  const failedReload = deferred<TimelineRecord | null>();
  const get = jest.fn((id: string) => (id === 'first' ? first.promise : failedReload.promise));
  const repository = createRepository(get);
  const view = await renderRoute(repository);

  await resolve(first, momentRecord('first', '第一条记录'));
  await waitFor(() => expect(view.getByLabelText('备注（可选）').props.value).toBe('第一条记录'));

  mockRouteId = 'second';
  await view.rerender(routeTree(repository));
  await reject(failedReload, new Error('database is unavailable'));

  expect(await view.findByText('无法读取记录，请重试')).toBeTruthy();
  expect(view.queryByLabelText('备注（可选）')).toBeNull();
  expect(view.getByRole('button', { name: '重试' })).toBeTruthy();
});

test('saves using the record id for the currently loaded route', async () => {
  const first = deferred<TimelineRecord | null>();
  const second = deferred<TimelineRecord | null>();
  const get = jest.fn((id: string) => (id === 'first' ? first.promise : second.promise));
  const update = jest.fn(async (id: string, input: NewRecordInput) => ({
    ...momentRecord(id, input.note ?? ''),
    occurredAt: input.occurredAt,
  }));
  const repository = createRepository(get, update);
  const view = await renderRoute(repository);

  await resolve(first, momentRecord('first', '第一条记录'));
  mockRouteId = 'second';
  await view.rerender(routeTree(repository));
  await resolve(second, momentRecord('second', '第二条记录'));
  await waitFor(() => expect(view.getByLabelText('备注（可选）').props.value).toBe('第二条记录'));

  await fireEvent.changeText(view.getByLabelText('备注（可选）'), '更新后的第二条记录');
  await fireEvent.press(view.getByRole('button', { name: '保存' }));

  await waitFor(() => expect(update).toHaveBeenCalledWith('second', expect.objectContaining({
    note: '更新后的第二条记录',
  })));
});

test('navigates after save and warns distinctly when old-media cleanup is pending', async () => {
  const record = momentRecord('first', '第一条记录', [{
    id: 'old-attachment',
    recordId: 'first',
    mediaType: 'image',
    filePath: 'file:///documents/media/old.jpg',
    thumbnailPath: null,
    createdAt: '2026-07-01T00:00:00.000Z',
  }]);
  const get = jest.fn(async () => record);
  const update = jest.fn(async (id: string, input: NewRecordInput) => ({
    ...momentRecord(id, input.note ?? ''),
    attachments: [],
  }));
  const media = routeMedia();
  media.remove.mockRejectedValue(new Error('old media is locked'));
  const showCleanupPending = jest.fn();
  const repository = createRepository(get, update);
  const view = await render(
    <RecordRepositoryProvider repository={repository}>
      <EditRecordRoute media={media} showCleanupPending={showCleanupPending} />
    </RecordRepositoryProvider>,
  );
  await waitFor(() => expect(view.getByLabelText('备注（可选）').props.value).toBe('第一条记录'));

  await fireEvent.press(view.getByRole('button', { name: '移除' }));
  await fireEvent.press(view.getByRole('button', { name: '保存' }));

  await waitFor(() => expect(mockReplace).toHaveBeenCalledWith('/record/first'));
  expect(showCleanupPending).toHaveBeenCalledWith('已保存，旧媒体将在稍后清理');
  expect(view.queryByText('保存失败，已有数据未受影响')).toBeNull();
});

function routeTree(repository: RecordRepository) {
  return (
    <RecordRepositoryProvider repository={repository}>
      <EditRecordRoute />
    </RecordRepositoryProvider>
  );
}

function renderRoute(repository: RecordRepository) {
  return render(routeTree(repository));
}

function createRepository(
  get: RecordRepository['get'],
  update: RecordRepository['update'] = async (id, input) => ({
    ...momentRecord(id, input.note ?? ''),
    occurredAt: input.occurredAt,
  }),
): RecordRepository {
  const memory = new MemoryRecordRepository();
  const transaction: RecordTransaction = {
    create: (input) => memory.create(input),
    update,
    delete: (id) => memory.delete(id),
  };
  return {
    create: (input) => memory.create(input),
    update,
    delete: (id) => memory.delete(id),
    get,
    list: (filter) => memory.list(filter),
    withTransaction: (work) => work(transaction),
  };
}

function momentRecord(
  id: string,
  note: string,
  attachments: TimelineRecord['attachments'] = [],
): TimelineRecord {
  return {
    id,
    type: 'moment',
    occurredAt: '2026-08-01T09:30:00.000Z',
    note,
    details: null,
    attachments,
    createdAt: '2026-08-01T09:30:00.000Z',
    updatedAt: '2026-08-01T09:30:00.000Z',
  };
}

function routeMedia(): jest.Mocked<MediaService> {
  return {
    stage: jest.fn(async (_input) => {
      throw new Error('No media should be staged in this test.');
    }),
    commit: jest.fn(async (_staged: StagedMedia) => {
      throw new Error('No media should be committed in this test.');
    }),
    rollback: jest.fn(async (_staged) => undefined),
    remove: jest.fn(async (_paths) => undefined),
    removeOrphans: jest.fn(async (_paths) => undefined),
  };
}

function deferred<T>() {
  let resolvePromise: (value: T) => void;
  let rejectPromise: (reason: unknown) => void;
  const promise = new Promise<T>((resolve, reject) => {
    resolvePromise = resolve;
    rejectPromise = reject;
  });
  return {
    promise,
    resolve: resolvePromise!,
    reject: rejectPromise!,
  };
}

async function resolve<T>(pending: ReturnType<typeof deferred<T>>, value: T) {
  await act(async () => {
    pending.resolve(value);
    await pending.promise;
  });
}

async function reject<T>(pending: ReturnType<typeof deferred<T>>, error: Error) {
  await act(async () => {
    pending.reject(error);
    try {
      await pending.promise;
    } catch {
      // The route converts lookup failures into a retry state.
    }
  });
}
