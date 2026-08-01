import { act, fireEvent, render } from '@testing-library/react-native';
import { Alert } from 'react-native';

import type { BackupService } from '../backupService';
import { BackupActions } from '../BackupActions';

describe('BackupActions', () => {
  beforeEach(() => {
    jest.restoreAllMocks();
  });

  test('requires the exact baby name after an explicit irreversible warning before clearing', async () => {
    const service = backupService();
    const view = await render(<BackupActions babyName="安安" service={service} />);

    await fireEvent.press(view.getByRole('button', { name: '清空全部数据' }));

    expect(view.getByText('此操作无法撤销。清空后所有记录与媒体都将删除。')).toBeTruthy();
    const confirm = view.getByRole('button', { name: '确认清空' });
    expect(confirm.props.accessibilityState.disabled).toBe(true);
    await fireEvent.changeText(view.getByLabelText('输入宝宝姓名确认'), '安安 ');
    expect(view.getByRole('button', { name: '确认清空' }).props.accessibilityState.disabled)
      .toBe(true);
    await fireEvent.changeText(view.getByLabelText('输入宝宝姓名确认'), '安安');
    expect(view.getByRole('button', { name: '确认清空' }).props.accessibilityState.disabled)
      .toBe(false);
    await fireEvent.press(view.getByRole('button', { name: '确认清空' }));

    expect(service.clear).toHaveBeenCalledTimes(1);
  });

  test('shows the retained archive path when sharing is unavailable', async () => {
    const service = backupService();
    service.export.mockResolvedValue({
      archivePath: 'file:///cache/backup.babygrowth.zip',
      shared: false,
    });
    const view = await render(<BackupActions babyName="安安" service={service} />);

    await fireEvent.press(view.getByRole('button', { name: '导出备份' }));

    expect(await view.findByText('备份已保留：file:///cache/backup.babygrowth.zip')).toBeTruthy();
  });

  test('does not open the picker when restore confirmation is cancelled', async () => {
    const service = backupService();
    const alert = jest.spyOn(Alert, 'alert');
    const view = await render(<BackupActions babyName="安安" service={service} />);

    await fireEvent.press(view.getByRole('button', { name: '从备份恢复' }));
    alert.mock.calls[0]?.[2]?.find((button) => button.text === '取消')?.onPress?.();

    expect(service.restore).not.toHaveBeenCalled();
  });

  test('surfaces cleanup pending after a successful clear and refreshes providers', async () => {
    const service = backupService();
    service.clear.mockResolvedValue({ cleanupPending: true, warning: '旧媒体被系统锁定' });
    const onDataChanged = jest.fn();
    const view = await render(
      <BackupActions babyName="安安" onDataChanged={onDataChanged} service={service} />,
    );
    await fireEvent.press(view.getByRole('button', { name: '清空全部数据' }));
    await fireEvent.changeText(view.getByLabelText('输入宝宝姓名确认'), '安安');

    await act(async () => {
      await fireEvent.press(view.getByRole('button', { name: '确认清空' }));
    });

    expect(await view.findByText('数据已清空；旧媒体被系统锁定')).toBeTruthy();
    expect(onDataChanged).toHaveBeenCalledTimes(1);
  });
});

function backupService(): jest.Mocked<BackupService> {
  return {
    export: jest.fn(async () => ({
      archivePath: 'file:///cache/backup.babygrowth.zip',
      shared: true,
    })),
    inspect: jest.fn(),
    restore: jest.fn<ReturnType<BackupService['restore']>, Parameters<BackupService['restore']>>(
      async () => ({ status: 'restored' }),
    ),
    clear: jest.fn(async () => ({ cleanupPending: false })),
  };
}
