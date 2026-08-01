import { act, fireEvent, render, screen, waitFor } from '@testing-library/react-native';

import type { RecordRepository } from '../../../data/repositories';
import RecordDetail from '../RecordDetail';
import { MemoryRecordRepository } from '../../../test/memoryRepositories';

test('shows growth measurements in cm and kg and a missing-media placeholder', async () => {
  const repository = new MemoryRecordRepository();
  const record = await repository.create({
    type: 'growth',
    occurredAt: '2026-08-02T09:30:00.000Z',
    note: '本月体检',
    details: { heightCm: 66.2, weightKg: 7.4, headCm: 42.1 },
    attachments: [
      {
        id: 'missing-photo',
        mediaType: 'image',
        filePath: '',
        thumbnailPath: null,
      },
    ],
  });

  const onEdit = jest.fn();

  await render(<RecordDetail repository={repository} recordId={record.id} onEdit={onEdit} />);

  await waitFor(() => expect(screen.getByText('身高 66.2 cm')).toBeTruthy());
  expect(screen.getByText('体重 7.4 kg')).toBeTruthy();
  expect(screen.getByText('头围 42.1 cm')).toBeTruthy();
  expect(screen.getByText('媒体文件不可用')).toBeTruthy();
  fireEvent.press(screen.getByRole('button', { name: '编辑' }));

  expect(onEdit).toHaveBeenCalledWith(`/record/edit/${record.id}`);
  expect(screen.getByRole('button', { name: '删除' }).props.accessibilityState.disabled).toBe(true);
});

test('shows a not-found state when the requested record does not exist', async () => {
  await render(<RecordDetail repository={new MemoryRecordRepository()} recordId="missing-record" />);

  await waitFor(() => expect(screen.getByText('记录不存在')).toBeTruthy());
});

test('retries a failed record lookup', async () => {
  const storedRepository = new MemoryRecordRepository();
  const record = await storedRepository.create({
    type: 'milestone',
    occurredAt: '2026-08-02T09:30:00.000Z',
    note: null,
    details: { title: '会翻身', presetKey: 'roll-over' },
    attachments: [],
  });
  let shouldFail = true;
  const retryingRepository: RecordRepository = {
    create: (input) => storedRepository.create(input),
    update: (id, input) => storedRepository.update(id, input),
    delete: (id) => storedRepository.delete(id),
    list: (filter) => storedRepository.list(filter),
    withTransaction: (work) => storedRepository.withTransaction(work),
    get: (id) => (shouldFail ? Promise.reject(new Error('database is unavailable')) : storedRepository.get(id)),
  };

  await render(<RecordDetail repository={retryingRepository} recordId={record.id} />);

  await waitFor(() => expect(screen.getByText('无法读取记录，请重试')).toBeTruthy());
  shouldFail = false;
  await act(async () => {
    fireEvent.press(screen.getByRole('button', { name: '重试' }));
    await Promise.resolve();
  });

  await waitFor(() => expect(screen.getByText('会翻身')).toBeTruthy());
});
