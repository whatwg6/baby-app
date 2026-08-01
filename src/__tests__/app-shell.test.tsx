import { render, screen, waitFor } from '@testing-library/react-native';

import AddScreen from '../../app/(tabs)/add';
import BabyScreen from '../../app/(tabs)/baby';
import TimelineScreen from '../../app/(tabs)/timeline';
import { BabyRepositoryProvider } from '../features/baby/useBaby';
import { RecordRepositoryProvider } from '../features/records/RecordRepositoryProvider';
import { babyInputFixture } from '../test/fixtures';
import { MemoryBabyRepository, MemoryRecordRepository } from '../test/memoryRepositories';

test('shows the empty timeline action', async () => {
  const babyRepository = new MemoryBabyRepository();
  await babyRepository.save(babyInputFixture());
  const recordRepository = new MemoryRecordRepository();

  await render(
    <BabyRepositoryProvider repository={babyRepository}>
      <RecordRepositoryProvider repository={recordRepository}>
        <TimelineScreen />
      </RecordRepositoryProvider>
    </BabyRepositoryProvider>,
  );

  await waitFor(() => expect(screen.getByText('还没有成长记录')).toBeTruthy());
  expect(screen.getByText('记录第一个瞬间')).toBeTruthy();
});

test('shows the add-record prompt', async () => {
  await render(<AddScreen />);

  expect(screen.getByText('选择记录类型')).toBeTruthy();
});

test('shows the baby profile heading', async () => {
  const repository = new MemoryBabyRepository();

  await render(
    <BabyRepositoryProvider repository={repository}>
      <BabyScreen />
    </BabyRepositoryProvider>,
  );

  expect(screen.getByText('宝宝资料')).toBeTruthy();
});
