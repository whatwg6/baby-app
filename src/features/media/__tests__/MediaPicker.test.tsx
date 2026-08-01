import { fireEvent, render, waitFor } from '@testing-library/react-native';
import * as ImagePicker from 'expo-image-picker';

import { MediaPicker } from '../MediaPicker';
import { MediaPreview } from '../MediaPreview';

const mockVideoPlay = jest.fn();

jest.mock('expo-video', () => {
  const { View } = require('react-native') as typeof import('react-native');
  return {
    useVideoPlayer: () => ({ play: mockVideoPlay }),
    VideoView: (props: Record<string, unknown>) => <View {...props} />,
  };
});

jest.mock('expo-image-picker', () => ({
  requestMediaLibraryPermissionsAsync: jest.fn(),
  launchImageLibraryAsync: jest.fn(),
}));

const requestPermission = ImagePicker.requestMediaLibraryPermissionsAsync as jest.MockedFunction<
  typeof ImagePicker.requestMediaLibraryPermissionsAsync
>;
const launchPicker = ImagePicker.launchImageLibraryAsync as jest.MockedFunction<
  typeof ImagePicker.launchImageLibraryAsync
>;

beforeEach(() => {
  jest.clearAllMocks();
});

test('shows a settings message when photo permission is denied', async () => {
  requestPermission.mockResolvedValue({
    granted: false,
    canAskAgain: false,
    expires: 'never',
    status: 'denied' as ImagePicker.PermissionStatus,
    accessPrivileges: 'none',
  });
  const onPick = jest.fn();
  const view = await render(<MediaPicker allowedMedia={['image']} onPick={onPick} />);

  await fireEvent.press(view.getByRole('button', { name: '选择图片' }));

  expect(await view.findByText('请在系统设置中允许访问照片')).toBeTruthy();
  expect(launchPicker).not.toHaveBeenCalled();
  expect(onPick).not.toHaveBeenCalled();
});

test('treats picker cancellation as a neutral outcome', async () => {
  requestPermission.mockResolvedValue({
    granted: true,
    canAskAgain: true,
    expires: 'never',
    status: 'granted' as ImagePicker.PermissionStatus,
    accessPrivileges: 'all',
  });
  launchPicker.mockResolvedValue({ canceled: true, assets: null });
  const onPick = jest.fn();
  const view = await render(<MediaPicker allowedMedia={['image', 'video']} onPick={onPick} />);

  await fireEvent.press(view.getByRole('button', { name: '选择图片或视频' }));

  await waitFor(() => expect(launchPicker).toHaveBeenCalledWith({
    allowsMultipleSelection: false,
    mediaTypes: ['images', 'videos'],
    quality: 1,
  }));
  expect(view.queryByText('请在系统设置中允许访问照片')).toBeNull();
  expect(onPick).not.toHaveBeenCalled();
});

test('returns the selected image using the domain media type', async () => {
  requestPermission.mockResolvedValue({
    granted: true,
    canAskAgain: true,
    expires: 'never',
    status: 'granted' as ImagePicker.PermissionStatus,
    accessPrivileges: 'all',
  });
  launchPicker.mockResolvedValue({
    canceled: false,
    assets: [{ uri: 'file:///picker/a.jpg', type: 'image', width: 100, height: 80 }],
  });
  const onPick = jest.fn();
  const view = await render(<MediaPicker allowedMedia={['image']} onPick={onPick} />);

  await fireEvent.press(view.getByRole('button', { name: '选择图片' }));

  await waitFor(() => expect(onPick).toHaveBeenCalledWith({
    kind: 'picked',
    sourceUri: 'file:///picker/a.jpg',
    mediaType: 'image',
  }));
});

test('shows a placeholder when an image preview fails to load', async () => {
  const view = await render(
    <MediaPreview mediaType="image" uri="file:///documents/media/missing.jpg" />,
  );

  await fireEvent(view.getByLabelText('媒体预览'), 'error');

  expect(view.getByLabelText('媒体文件不可用')).toBeTruthy();
});

test('plays a private video attachment in the preview instead of rendering a placeholder', async () => {
  const view = await render(
    <MediaPreview mediaType="video" uri="file:///documents/media/first-step.mp4" />,
  );

  expect(view.queryByText('媒体文件不可用')).toBeNull();
  await fireEvent.press(view.getByRole('button', { name: '播放视频' }));
  expect(mockVideoPlay).toHaveBeenCalledTimes(1);
});
