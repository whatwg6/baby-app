import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react-native';

import type {
  RecordListOptions,
  RecordPage,
  RecordPageCursor,
  RecordRepository,
} from '../../../data/repositories';
import type { Baby, TimelineRecord } from '../../../domain/types';
import { MemoryRecordRepository } from '../../../test/memoryRepositories';
import { momentInputFixture } from '../../../test/fixtures';
import TimelineScreen from '../TimelineScreen';

jest.mock('expo-video', () => {
  const { View } = require('react-native') as typeof import('react-native');
  return {
    useVideoPlayer: () => ({ play: jest.fn() }),
    VideoView: (props: Record<string, unknown>) => <View {...props} />,
  };
});

jest.mock('react-native', () => {
  const React = require('react') as typeof import('react');
  const actual = jest.requireActual('react-native') as typeof import('react-native');
  const TestScrollView = actual.ScrollView as unknown as React.ComponentType<Record<string, any>>;
  const SynchronousSectionList = (props: Record<string, any>) => React.createElement(
    TestScrollView,
    {
      contentContainerStyle: props.contentContainerStyle,
      onEndReached: props.onEndReached,
      testID: props.testID,
    },
    props.ListHeaderComponent,
    ...props.sections.flatMap((section: Record<string, any>) => [
      React.createElement(
        React.Fragment,
        { key: `${section.key}-header` },
        props.renderSectionHeader({ section }),
      ),
      ...section.data.map((item: TimelineRecord, index: number) => React.createElement(
        React.Fragment,
        { key: props.keyExtractor(item, index) },
        props.renderItem({ index, item, section }),
      )),
    ]),
    props.ListFooterComponent,
  );
  Object.defineProperty(actual, 'SectionList', {
    configurable: true,
    value: SynchronousSectionList,
  });
  return actual;
});

const baby: Baby = {
  id: 'baby-1',
  name: '安安',
  birthDate: '2026-01-15',
  sex: 'female',
  avatarPath: null,
  createdAt: '2026-01-15T00:00:00.000Z',
  updatedAt: '2026-01-15T00:00:00.000Z',
};

async function pressAndFlush(element: Parameters<typeof fireEvent.press>[0]) {
  await act(async () => {
    fireEvent.press(element);
    await Promise.resolve();
  });
}

test('shows records in descending day order with type-specific summaries', async () => {
  const repository = new MemoryRecordRepository();
  await repository.create(momentInputFixture({ occurredAt: '2026-08-01T09:30:00.000Z' }));
  await repository.create({
    type: 'growth',
    occurredAt: '2026-08-03T09:30:00.000Z',
    note: null,
    details: { heightCm: 66.2, weightKg: 7.4, headCm: null },
    attachments: [],
  });
  await repository.create({
    type: 'activity',
    occurredAt: '2026-08-02T13:00:00.000Z',
    note: '午后小睡',
    details: { activityType: 'sleep', amount: null, durationMinutes: 45 },
    attachments: [],
  });

  await render(<TimelineScreen repository={repository} baby={baby} />);

  await waitFor(() => expect(screen.getByText('身高 66.2 cm · 体重 7.4 kg')).toBeTruthy());
  expect(screen.getByText('睡眠 · 45 分钟')).toBeTruthy();
  expect(screen.getByText('第一次看向镜头')).toBeTruthy();

  const dayHeadings = screen.getAllByLabelText(/时间轴日期/);
  expect(dayHeadings.map((heading) => heading.props.children)).toEqual([
    '2026年8月3日',
    '2026年8月2日',
    '今天',
  ]);
});

test('renders timeline records through a virtualized section list', async () => {
  const repository = new MemoryRecordRepository();
  await repository.create(momentInputFixture());

  const view = await render(<TimelineScreen repository={repository} baby={baby} />);

  await view.findByText('第一次看向镜头');
  expect(view.queryByTestId('timeline-section-list')).toBeTruthy();
});

test('loads the next page at the list end and retains loaded records while retrying a failure', async () => {
  const first = timelineMoment('first-page', '第一页', '2026-08-03T09:30:00.000Z');
  const second = timelineMoment('second-page', '第二页', '2026-08-02T09:30:00.000Z');
  const cursor: RecordPageCursor = {
    occurredAt: '2026-08-03T09:30:00.000Z',
    createdAt: '2026-08-03T09:31:00.000Z',
    id: 'first-page',
  };
  let nextPageShouldFail = true;
  const calls: RecordListOptions[] = [];
  const repository = pagedRepository(async (options) => {
    calls.push(options);
    if (options.cursor === null || options.cursor === undefined) {
      return { records: [first], nextCursor: cursor };
    }
    if (nextPageShouldFail) {
      nextPageShouldFail = false;
      throw new Error('database is unavailable');
    }
    return { records: [second], nextCursor: null };
  });

  const view = await render(<TimelineScreen repository={repository} baby={baby} />);
  await view.findByText('第一页');

  await act(async () => {
    fireEvent(view.getByTestId('timeline-section-list'), 'endReached');
    await Promise.resolve();
    await Promise.resolve();
  });

  const loadMoreError = await view.findByTestId('timeline-load-more-error');
  expect(within(loadMoreError).getByText('无法读取记录，请重试')).toBeTruthy();
  expect(view.getByText('第一页')).toBeTruthy();
  expect(view.queryByText('第二页')).toBeNull();

  await pressAndFlush(within(loadMoreError).getByRole('button', { name: '重试' }));

  await waitFor(() => expect(view.getByText('第二页')).toBeTruthy());
  expect(view.getByText('第一页')).toBeTruthy();
  expect(calls).toEqual([
    { types: [], cursor: null, limit: 20 },
    { types: [], cursor, limit: 20 },
    { types: [], cursor, limit: 20 },
  ]);
});

test('starts a fresh cursor chain for filters and ignores a stale previous response', async () => {
  const stalePage = deferred<RecordPage>();
  const growth = timelineGrowth('growth-filter', '2026-08-04T09:30:00.000Z');
  const staleMoment = timelineMoment('stale-moment', '不应出现的旧记录', '2026-08-03T09:30:00.000Z');
  const calls: RecordListOptions[] = [];
  const repository = pagedRepository((options) => {
    calls.push(options);
    return options.types?.includes('growth')
      ? Promise.resolve({ records: [growth], nextCursor: null })
      : stalePage.promise;
  });

  const view = await render(<TimelineScreen repository={repository} baby={baby} />);
  await waitFor(() => expect(calls).toHaveLength(1));

  await pressAndFlush(view.getByRole('button', { name: '成长数据' }));
  expect(await view.findByText('身高 68 cm')).toBeTruthy();

  await resolveDeferred(stalePage, { records: [staleMoment], nextCursor: null });

  expect(view.queryByText('不应出现的旧记录')).toBeNull();
  expect(view.getByText('身高 68 cm')).toBeTruthy();
  expect(calls).toEqual([
    { types: [], cursor: null, limit: 20 },
    { types: ['growth'], cursor: null, limit: 20 },
  ]);
});

test('filters by selected type and returns to all types when the selection is cleared', async () => {
  const repository = new MemoryRecordRepository();
  await repository.create(momentInputFixture());
  await repository.create({
    type: 'growth',
    occurredAt: '2026-08-02T09:30:00.000Z',
    note: null,
    details: { heightCm: 66.2, weightKg: 7.4, headCm: null },
    attachments: [],
  });

  await render(<TimelineScreen repository={repository} baby={baby} />);

  await waitFor(() => expect(screen.getByText('第一次看向镜头')).toBeTruthy());
  await pressAndFlush(screen.getByRole('button', { name: '成长数据' }));

  await waitFor(() => expect(screen.queryByText('第一次看向镜头')).toBeNull());
  expect(screen.getByText('身高 66.2 cm · 体重 7.4 kg')).toBeTruthy();

  await pressAndFlush(screen.getByRole('button', { name: '成长数据' }));

  await waitFor(() => expect(screen.getByText('第一次看向镜头')).toBeTruthy());
});

test('shows an empty state when there are no records', async () => {
  await render(<TimelineScreen repository={new MemoryRecordRepository()} baby={baby} />);

  await waitFor(() => expect(screen.getByText('还没有成长记录')).toBeTruthy());
  expect(screen.getByText('记录第一个瞬间')).toBeTruthy();
});

test('emits the selected record when a timeline card is pressed', async () => {
  const repository = new MemoryRecordRepository();
  const record = await repository.create(momentInputFixture());
  const onRecordPress = jest.fn();

  await render(<TimelineScreen repository={repository} baby={baby} onRecordPress={onRecordPress} />);

  const card = await screen.findByLabelText(`时间轴记录 ${record.id}`);
  fireEvent.press(card);

  expect(onRecordPress).toHaveBeenCalledWith(record);
});

test('shows a media placeholder when a moment image fails to load', async () => {
  const repository = new MemoryRecordRepository();
  await repository.create(momentInputFixture());

  await render(<TimelineScreen repository={repository} baby={baby} />);

  const image = await screen.findByLabelText('珍贵时刻照片');
  fireEvent(image, 'error');

  await waitFor(() => expect(screen.getByText('媒体文件不可用')).toBeTruthy());
});

test('renders video playback for a video-only moment without a missing-media placeholder', async () => {
  const repository = new MemoryRecordRepository();
  await repository.create({
    type: 'moment',
    occurredAt: '2026-08-01T09:30:00.000Z',
    note: null,
    details: null,
    attachments: [{
      id: 'video-1',
      mediaType: 'video',
      filePath: 'file:///documents/media/first-step.mp4',
      thumbnailPath: null,
    }],
  });

  await render(<TimelineScreen repository={repository} baby={baby} />);

  expect(await screen.findByRole('button', { name: '播放视频' })).toBeTruthy();
  expect(screen.queryByText('媒体文件不可用')).toBeNull();
});

test('retains displayed records and offers retry when a reload fails', async () => {
  const populatedRepository = new MemoryRecordRepository();
  await populatedRepository.create(momentInputFixture());
  let shouldFail = true;
  const retryingRepository: RecordRepository = {
    create: (input) => populatedRepository.create(input),
    update: (id, input) => populatedRepository.update(id, input),
    delete: (id) => populatedRepository.delete(id),
    get: (id) => populatedRepository.get(id),
    withTransaction: (work) => populatedRepository.withTransaction(work),
    list: (filter) => populatedRepository.list(filter),
    listPage: (options) => {
      if (shouldFail) {
        return Promise.reject(new Error('database is unavailable'));
      }
      return populatedRepository.listPage(options);
    },
  };

  const view = await render(<TimelineScreen repository={populatedRepository} baby={baby} />);
  await waitFor(() => expect(screen.getByText('第一次看向镜头')).toBeTruthy());

  await view.rerender(<TimelineScreen repository={retryingRepository} baby={baby} />);

  await waitFor(() => expect(screen.getByText('无法读取记录，请重试')).toBeTruthy());
  expect(screen.getByText('第一次看向镜头')).toBeTruthy();
  expect(screen.queryByTestId('timeline-load-more-error')).toBeNull();

  shouldFail = false;
  await pressAndFlush(screen.getByRole('button', { name: '重试' }));

  await waitFor(() => expect(screen.queryByText('无法读取记录，请重试')).toBeNull());
  expect(screen.getByText('第一次看向镜头')).toBeTruthy();
});

function pagedRepository(
  listPage: (options: RecordListOptions) => Promise<RecordPage>,
): RecordRepository {
  const backing = new MemoryRecordRepository();
  return {
    create: (input) => backing.create(input),
    update: (id, input) => backing.update(id, input),
    delete: (id) => backing.delete(id),
    get: (id) => backing.get(id),
    list: (filter) => backing.list(filter),
    listPage: (options = {}) => listPage({
      types: options.types ?? [],
      cursor: options.cursor ?? null,
      limit: options.limit,
    }),
    withTransaction: (work) => backing.withTransaction(work),
  };
}

function timelineMoment(
  id: string,
  note: string,
  occurredAt: string,
): TimelineRecord {
  return {
    id,
    type: 'moment',
    occurredAt,
    note,
    details: null,
    attachments: [],
    createdAt: occurredAt.replace('09:30', '09:31'),
    updatedAt: occurredAt.replace('09:30', '09:31'),
  };
}

function timelineGrowth(id: string, occurredAt: string): TimelineRecord {
  return {
    id,
    type: 'growth',
    occurredAt,
    note: null,
    details: { heightCm: 68, weightKg: null, headCm: null },
    attachments: [],
    createdAt: occurredAt.replace('09:30', '09:31'),
    updatedAt: occurredAt.replace('09:30', '09:31'),
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, reject, resolve };
}

async function resolveDeferred<T>(pending: ReturnType<typeof deferred<T>>, value: T) {
  await act(async () => {
    pending.resolve(value);
    await pending.promise;
  });
}
