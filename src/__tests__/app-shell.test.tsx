import { fireEvent, render, screen, waitFor } from '@testing-library/react-native';

import AddScreen from '../../app/(tabs)/add';
import BabyScreen from '../../app/(tabs)/baby';
import TimelineScreen from '../../app/(tabs)/timeline';
import { BabyRepositoryProvider } from '../features/baby/useBaby';
import { BackupServiceProvider } from '../features/backup/BackupActions';
import type { BackupService } from '../features/backup/backupService';
import { RecordRepositoryProvider } from '../features/records/RecordRepositoryProvider';
import { babyInputFixture } from '../test/fixtures';
import { MemoryBabyRepository, MemoryRecordRepository } from '../test/memoryRepositories';

const mockPush = jest.fn();
const mockReplace = jest.fn();

jest.mock('expo-router', () => ({
  useRouter: () => ({ push: mockPush, replace: mockReplace }),
}));

jest.mock('expo-video', () => {
  const { View } = require('react-native') as typeof import('react-native');
  return {
    useVideoPlayer: () => ({ play: jest.fn() }),
    VideoView: (props: Record<string, unknown>) => <View {...props} />,
  };
});

beforeEach(() => {
  jest.clearAllMocks();
});

test('opens the add-record route from the empty timeline action', async () => {
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
  fireEvent.press(screen.getByRole('button', { name: '记录第一个瞬间' }));

  expect(mockPush).toHaveBeenCalledWith('/(tabs)/add');
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

test('shows backup and destructive data actions for an existing baby', async () => {
  const repository = new MemoryBabyRepository();
  await repository.save(babyInputFixture());
  const backup: jest.Mocked<BackupService> = {
    export: jest.fn(),
    inspect: jest.fn(),
    restore: jest.fn(),
    clear: jest.fn(),
  };

  await render(
    <BackupServiceProvider service={backup}>
      <BabyRepositoryProvider repository={repository}>
        <BabyScreen />
      </BabyRepositoryProvider>
    </BackupServiceProvider>,
  );

  expect(await screen.findByRole('button', { name: '导出备份' })).toBeTruthy();
  expect(screen.getByRole('button', { name: '从备份恢复' })).toBeTruthy();
  expect(screen.getByRole('button', { name: '清空全部数据' })).toBeTruthy();
});
