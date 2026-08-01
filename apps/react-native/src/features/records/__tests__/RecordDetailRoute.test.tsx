import { act, fireEvent, render, waitFor } from '@testing-library/react-native';
import { Alert } from 'react-native';

import RecordDetailRoute from '../../../../app/record/[id]';
import { AppProvider, type AppServices } from '../../../app/AppProvider';
import type { BackupService } from '../../backup/backupService';
import type { MediaService, StagedMedia } from '../../media/mediaService';
import { MemoryBabyRepository, MemoryRecordRepository } from '../../../test/memoryRepositories';

const mockReplace = jest.fn();
let mockRecordId = '';

jest.mock('expo-router', () => ({
  useLocalSearchParams: () => ({ id: mockRecordId }),
  useRouter: () => ({ push: jest.fn(), replace: mockReplace }),
}));

jest.mock('expo-video', () => {
  const { View } = require('react-native') as typeof import('react-native');
  return {
    useVideoPlayer: () => ({ play: jest.fn() }),
    VideoView: (props: Record<string, unknown>) => <View {...props} />,
  };
});

test('publishes a durable cleanup warning before navigating away from a deleted record', async () => {
  const records = new MemoryRecordRepository();
  const created = await records.create({
    type: 'moment',
    occurredAt: '2026-08-01T09:30:00.000Z',
    note: '第一次散步',
    details: null,
    attachments: [{
      id: 'attachment-1',
      mediaType: 'image',
      filePath: 'file:///documents/media/photo.jpg',
      thumbnailPath: null,
    }],
  });
  mockRecordId = created.id;
  const media: jest.Mocked<MediaService> = {
    stage: jest.fn<ReturnType<MediaService['stage']>, Parameters<MediaService['stage']>>(),
    commit: jest.fn<ReturnType<MediaService['commit']>, Parameters<MediaService['commit']>>(),
    rollback: jest.fn(async (_staged: StagedMedia) => undefined),
    remove: jest.fn(async (_paths: string[]) => {
      throw new Error('media is locked');
    }),
    removeOrphans: jest.fn(async (_paths: string[]) => undefined),
  };
  const reportCleanupWarning = jest.fn();
  const services: AppServices = {
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
    reportCleanupWarning,
  };
  const alert = jest.spyOn(Alert, 'alert');
  const view = await render(
    <AppProvider services={services}>
      <RecordDetailRoute />
    </AppProvider>,
  );

  await fireEvent.press(await view.findByRole('button', { name: '删除' }));
  await act(async () => {
    alert.mock.calls[0]?.[2]?.find((button) => button.text === '删除')?.onPress?.();
    await Promise.resolve();
    await Promise.resolve();
  });

  await waitFor(() => expect(reportCleanupWarning).toHaveBeenCalledWith(
    '记录已删除，媒体将在稍后清理',
  ));
  expect(mockReplace).toHaveBeenCalledWith('/(tabs)/timeline');
  expect(reportCleanupWarning.mock.invocationCallOrder[0]).toBeLessThan(
    mockReplace.mock.invocationCallOrder[0] ?? Number.POSITIVE_INFINITY,
  );
});
