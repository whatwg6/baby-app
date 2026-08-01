import { fireEvent, render, waitFor } from '@testing-library/react-native';
import * as ImagePicker from 'expo-image-picker';

import BabySetupScreen from '../../../../app/baby/setup';
import type { MediaService, StagedMedia } from '../../media/mediaService';
import { MemoryBabyRepository } from '../../../test/memoryRepositories';
import { BabyRepositoryProvider } from '../useBaby';

const mockReplace = jest.fn();

jest.mock('expo-router', () => ({
  useRouter: () => ({ replace: mockReplace }),
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

test('first-run setup coordinates a picked avatar into private media before navigation', async () => {
  requestPermission.mockResolvedValue({
    granted: true,
    canAskAgain: true,
    expires: 'never',
    status: 'granted' as ImagePicker.PermissionStatus,
    accessPrivileges: 'all',
  });
  launchPicker.mockResolvedValue({
    canceled: false,
    assets: [{ uri: 'file:///picker/setup.jpg', type: 'image', width: 100, height: 100 }],
  });
  const babies = new MemoryBabyRepository();
  const media = avatarMedia();
  const view = await render(
    <BabyRepositoryProvider media={media} repository={babies}>
      <BabySetupScreen />
    </BabyRepositoryProvider>,
  );

  await view.findByText('先认识一下宝宝');
  await fireEvent.changeText(view.getByLabelText('宝宝姓名'), '安安');
  await fireEvent.changeText(view.getByLabelText('出生日期'), '2025-06-15');
  await fireEvent.press(view.getByRole('button', { name: '选择图片' }));
  await fireEvent.press(view.getByRole('button', { name: '保存' }));

  await waitFor(() => expect(media.stage).toHaveBeenCalledWith({
    uri: 'file:///picker/setup.jpg',
    mediaType: 'image',
  }));
  await expect(babies.get()).resolves.toMatchObject({
    avatarPath: 'file:///documents/media/setup.jpg',
  });
  expect(mockReplace).toHaveBeenCalledWith('/(tabs)/timeline');
});

test('keeps setup controls reachable in a keyboard-aware scroll container', async () => {
  const view = await render(
    <BabyRepositoryProvider media={avatarMedia()} repository={new MemoryBabyRepository()}>
      <BabySetupScreen />
    </BabyRepositoryProvider>,
  );

  await view.findByText('先认识一下宝宝');

  expect(view.queryByTestId('baby-setup-keyboard-avoiding')).toBeTruthy();
  expect(view.getByTestId('baby-setup-scroll').props.keyboardShouldPersistTaps).toBe('handled');
  expect(view.getByRole('button', { name: '保存' })).toBeTruthy();
});

function avatarMedia(): jest.Mocked<MediaService> {
  const staged: StagedMedia = {
    stagingPath: 'file:///documents/staging/setup.jpg',
    finalPath: 'file:///documents/media/setup.jpg',
    mediaType: 'image',
    thumbnailStagingPath: 'file:///documents/staging/setup-thumb.jpg',
    thumbnailFinalPath: 'file:///documents/media/setup-thumb.jpg',
  };
  return {
    stage: jest.fn(async (_input: Parameters<MediaService['stage']>[0]) => staged),
    commit: jest.fn(async (_staged: StagedMedia) => ({
      filePath: staged.finalPath,
      thumbnailPath: staged.thumbnailFinalPath,
    })),
    rollback: jest.fn(async (_staged: StagedMedia) => undefined),
    remove: jest.fn(async (_paths: string[]) => undefined),
    removeOrphans: jest.fn(async (_paths: string[]) => undefined),
  };
}
