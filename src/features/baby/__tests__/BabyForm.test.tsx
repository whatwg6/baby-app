import { fireEvent, render, waitFor } from '@testing-library/react-native';

import BabyForm from '../BabyForm';

describe('BabyForm', () => {
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

    const view = await render(
      <BabyForm now={new Date(2026, 7, 1, 12)} onSave={onSave} />,
    );

    await fireEvent.changeText(view.getByLabelText('宝宝姓名'), '安安');
    await fireEvent.changeText(view.getByLabelText('出生日期'), '2025-06-15');
    await fireEvent.press(view.getByRole('button', { name: '女' }));
    await fireEvent.changeText(view.getByLabelText('头像路径（可选）'), 'file:///avatars/anan.jpg');
    await fireEvent.press(view.getByText('保存'));

    await waitFor(() => expect(onSave).toHaveBeenCalledWith({
      name: '安安',
      birthDate: '2025-06-15',
      sex: 'female',
      avatarPath: 'file:///avatars/anan.jpg',
    }));
  });
});
