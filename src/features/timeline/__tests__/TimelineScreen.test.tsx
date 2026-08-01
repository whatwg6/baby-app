import { act, fireEvent, render, screen, waitFor } from '@testing-library/react-native';

import type { RecordRepository } from '../../../data/repositories';
import type { Baby } from '../../../domain/types';
import { MemoryRecordRepository } from '../../../test/memoryRepositories';
import { momentInputFixture } from '../../../test/fixtures';
import TimelineScreen from '../TimelineScreen';

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
    list: (filter) => {
      if (shouldFail) {
        return Promise.reject(new Error('database is unavailable'));
      }
      return populatedRepository.list(filter);
    },
  };

  const view = await render(<TimelineScreen repository={populatedRepository} baby={baby} />);
  await waitFor(() => expect(screen.getByText('第一次看向镜头')).toBeTruthy());

  await view.rerender(<TimelineScreen repository={retryingRepository} baby={baby} />);

  await waitFor(() => expect(screen.getByText('无法读取记录，请重试')).toBeTruthy());
  expect(screen.getByText('第一次看向镜头')).toBeTruthy();

  shouldFail = false;
  await pressAndFlush(screen.getByRole('button', { name: '重试' }));

  await waitFor(() => expect(screen.queryByText('无法读取记录，请重试')).toBeNull());
  expect(screen.getByText('第一次看向镜头')).toBeTruthy();
});
