import { act, fireEvent, render, waitFor } from '@testing-library/react-native';

import type { RecordDraft } from '../../../domain/types';
import { RecordEditor, toNewRecordInput } from '../RecordEditor';

const now = new Date('2026-08-01T09:30:00.000Z');

describe('RecordEditor', () => {
  test('does not save an empty moment', async () => {
    const onSubmit = jest.fn();
    const view = await render(<RecordEditor now={now} onSubmit={onSubmit} type="moment" />);

    await fireEvent.press(view.getByRole('button', { name: '保存' }));

    expect(await view.findByText('请填写文字或添加媒体')).toBeTruthy();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  test('saves a growth record with one valid measurement', async () => {
    const onSubmit = jest.fn();
    const view = await render(<RecordEditor now={now} onSubmit={onSubmit} type="growth" />);

    await fireEvent.changeText(view.getByLabelText('身高（cm）'), '66.2');
    await fireEvent.press(view.getByRole('button', { name: '保存' }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledWith({
      type: 'growth',
      occurredAt: '2026-08-01T09:30:00.000Z',
      note: null,
      details: { heightCm: 66.2, weightKg: null, headCm: null },
      attachments: [],
    }));
  });

  test('keeps a partial decimal while a growth measurement is being entered', async () => {
    const view = await render(<RecordEditor now={now} onSubmit={jest.fn()} type="growth" />);

    await fireEvent.changeText(view.getByLabelText('身高（cm）'), '66.');

    expect(view.getByLabelText('身高（cm）').props.value).toBe('66.');
  });

  test('requires an activity type', async () => {
    const onSubmit = jest.fn();
    const view = await render(<RecordEditor now={now} onSubmit={onSubmit} type="activity" />);

    await fireEvent.changeText(view.getByLabelText('备注（可选）'), '午后小睡');
    await fireEvent.press(view.getByRole('button', { name: '保存' }));

    expect(await view.findByText('请选择活动类型')).toBeTruthy();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  test('requires a milestone title', async () => {
    const onSubmit = jest.fn();
    const view = await render(<RecordEditor now={now} onSubmit={onSubmit} type="milestone" />);

    await fireEvent.press(view.getByRole('button', { name: '保存' }));

    expect(await view.findByText('请填写里程碑标题')).toBeTruthy();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  test('defaults the occurrence time and lets it be edited', async () => {
    const onSubmit = jest.fn();
    const view = await render(<RecordEditor now={now} onSubmit={onSubmit} type="moment" />);

    expect(view.getByLabelText('发生时间').props.value).toBe('2026-08-01T09:30:00.000Z');
    await fireEvent.changeText(view.getByLabelText('发生时间'), '2026-07-31T18:20:00.000Z');
    await fireEvent.changeText(view.getByLabelText('备注（可选）'), '傍晚散步');
    await fireEvent.press(view.getByRole('button', { name: '保存' }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledWith(expect.objectContaining({
      occurredAt: '2026-07-31T18:20:00.000Z',
    })));
  });

  test('fills an edit form with its existing values and attachments', async () => {
    const initialValue: RecordDraft = {
      type: 'activity',
      occurredAt: '2026-07-31T18:20:00.000Z',
      note: '午后小睡',
      details: { activityType: 'sleep', amount: null, durationMinutes: 45 },
      attachments: [{
        kind: 'existing',
        id: 'attachment-1',
        mediaType: 'image',
        filePath: 'file:///media/sleep.jpg',
        thumbnailPath: null,
      }],
    };
    const onSubmit = jest.fn();
    const view = await render(
      <RecordEditor initialValue={initialValue} now={now} onSubmit={onSubmit} type="activity" />,
    );

    expect(view.getByLabelText('发生时间').props.value).toBe('2026-07-31T18:20:00.000Z');
    expect(view.getByLabelText('备注（可选）').props.value).toBe('午后小睡');
    expect(view.getByLabelText('数量（可选）').props.value).toBe('');
    expect(view.getByLabelText('时长（分钟，可选）').props.value).toBe('45');
    expect(view.getByRole('button', { name: '睡眠' }).props.accessibilityState.selected).toBe(true);

    await fireEvent.press(view.getByRole('button', { name: '保存' }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledWith(initialValue));
  });

  test('keeps the current values and reports a save failure', async () => {
    const onSubmit = jest.fn().mockRejectedValue(new Error('database is unavailable'));
    const view = await render(<RecordEditor now={now} onSubmit={onSubmit} type="moment" />);

    await fireEvent.changeText(view.getByLabelText('备注（可选）'), '第一次散步');
    await fireEvent.press(view.getByRole('button', { name: '保存' }));

    expect(await view.findByText('保存失败，已有数据未受影响')).toBeTruthy();
    expect(view.getByLabelText('备注（可选）').props.value).toBe('第一次散步');
  });

  test('submits only once while a save is pending', async () => {
    let finishSave: (() => void) | undefined;
    const onSubmit = jest.fn(() => new Promise<void>((resolve) => {
      finishSave = resolve;
    }));
    const view = await render(<RecordEditor now={now} onSubmit={onSubmit} type="moment" />);

    await fireEvent.changeText(view.getByLabelText('备注（可选）'), '第一次散步');
    const saveButton = view.getByText('保存').parent;
    if (saveButton === null) {
      throw new Error('Save button was not rendered.');
    }
    await act(async () => {
      saveButton.props.onClick({} as never);
      saveButton.props.onClick({} as never);
    });

    expect(onSubmit).toHaveBeenCalledTimes(1);
    await act(async () => {
      finishSave?.();
    });
  });

  test('maps existing edit attachments to repository input', () => {
    const input = toNewRecordInput({
      type: 'moment',
      occurredAt: '2026-08-01T09:30:00.000Z',
      note: '第一次散步',
      details: null,
      attachments: [{
        kind: 'existing',
        id: 'attachment-1',
        mediaType: 'image',
        filePath: 'file:///media/walk.jpg',
        thumbnailPath: 'file:///media/walk-thumb.jpg',
      }],
    });

    expect(input.attachments).toEqual([{
      id: 'attachment-1',
      mediaType: 'image',
      filePath: 'file:///media/walk.jpg',
      thumbnailPath: 'file:///media/walk-thumb.jpg',
    }]);
  });
});
