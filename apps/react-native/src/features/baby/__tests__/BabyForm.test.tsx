import { fireEvent, render, waitFor } from '@testing-library/react-native';
import * as ImagePicker from 'expo-image-picker';

import BabyForm from '../BabyForm';
import { MediaServiceError } from '../../media/mediaService';

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

describe('BabyForm', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('shows an error below the name field when the name is empty', async () => {
    const onSave = jest.fn();

    const view = await render(
      <BabyForm now={new Date(2026, 7, 1, 12)} onSave={onSave} />,
    );

    await fireEvent.changeText(view.getByLabelText('出生日期'), '2025-06-15');
    await fireEvent.press(view.getByText('保存'));

    expect(await view.findByText('请填写宝宝姓名')).toBeTruthy();
    expect(onSave).not.toHaveBeenCalled();
  });

  test('shows an error below the birth date field when the date is in the future', async () => {
    const onSave = jest.fn();

    const view = await render(
      <BabyForm now={new Date(2026, 7, 1, 12)} onSave={onSave} />,
    );

    await fireEvent.changeText(view.getByLabelText('宝宝姓名'), '安安');
    await fireEvent.changeText(view.getByLabelText('出生日期'), '2026-08-02');
    await fireEvent.press(view.getByText('保存'));

    expect(await view.findByText('出生日期不能晚于今天')).toBeTruthy();
    expect(onSave).not.toHaveBeenCalled();
  });

  test('shows an invalid-date error for a malformed calendar date', async () => {
    const onSave = jest.fn();

    const view = await render(
      <BabyForm now={new Date(2026, 7, 1, 12)} onSave={onSave} />,
    );

    await fireEvent.changeText(view.getByLabelText('宝宝姓名'), '安安');
    await fireEvent.changeText(view.getByLabelText('出生日期'), '2025-02-30');
    await fireEvent.press(view.getByText('保存'));

    expect(await view.findByText('请输入有效的出生日期')).toBeTruthy();
    expect(onSave).not.toHaveBeenCalled();
  });

  test('saves a valid profile with selected optional values', async () => {
    const onSave = jest.fn();
    requestPermission.mockResolvedValue({
      granted: true,
      canAskAgain: true,
      expires: 'never',
      status: 'granted' as ImagePicker.PermissionStatus,
      accessPrivileges: 'all',
    });
    launchPicker.mockResolvedValue({
      canceled: false,
      assets: [{ uri: 'file:///picker/anan.jpg', type: 'image', width: 100, height: 100 }],
    });

    const view = await render(
      <BabyForm now={new Date(2026, 7, 1, 12)} onSave={onSave} />,
    );

    await fireEvent.changeText(view.getByLabelText('宝宝姓名'), '安安');
    await fireEvent.changeText(view.getByLabelText('出生日期'), '2025-06-15');
    await fireEvent.press(view.getByRole('button', { name: '女' }));
    await fireEvent.press(view.getByRole('button', { name: '选择图片' }));
    await fireEvent.press(view.getByText('保存'));

    await waitFor(() => expect(onSave).toHaveBeenCalledWith({
      name: '安安',
      birthDate: '2025-06-15',
      sex: 'female',
      avatarPath: 'file:///picker/anan.jpg',
    }, { sourceUri: 'file:///picker/anan.jpg' }));
  });

  test('shows a displayable avatar storage error', async () => {
    const onSave = jest.fn().mockRejectedValue(
      new MediaServiceError('insufficient-space', '设备存储空间不足，请清理后重试'),
    );
    const view = await render(
      <BabyForm now={new Date(2026, 7, 1, 12)} onSave={onSave} />,
    );

    await fireEvent.changeText(view.getByLabelText('宝宝姓名'), '安安');
    await fireEvent.changeText(view.getByLabelText('出生日期'), '2025-06-15');
    await fireEvent.press(view.getByText('保存'));

    expect(await view.findByText('设备存储空间不足，请清理后重试')).toBeTruthy();
  });
});
