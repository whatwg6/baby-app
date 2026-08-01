import { act, fireEvent, render, waitFor } from '@testing-library/react-native';
import { Alert } from 'react-native';

import type { RecordRepository } from '../../../data/repositories';
import type { MediaService } from '../../media/mediaService';
import DeleteRecordButton from '../DeleteRecordButton';

describe('DeleteRecordButton', () => {
  beforeEach(() => {
    jest.restoreAllMocks();
  });

  test('requires the explicit irreversible confirmation and cancel leaves the repository untouched', async () => {
    const { repository, media } = dependencies();
    const alert = jest.spyOn(Alert, 'alert');
    const view = await render(
      <DeleteRecordButton media={media} recordId="record-1" repository={repository} />,
    );

    await fireEvent.press(view.getByRole('button', { name: '删除' }));

    expect(alert).toHaveBeenCalledWith(
      '删除这条记录？此操作无法撤销。',
      undefined,
      expect.arrayContaining([expect.objectContaining({ text: '取消' })]),
    );
    const buttons = alert.mock.calls[0]?.[2];
    buttons?.find((button) => button.text === '取消')?.onPress?.();
    expect(repository.delete).not.toHaveBeenCalled();
    expect(media.remove).not.toHaveBeenCalled();
  });

  test('deletes the database record first, then removes every returned attachment path', async () => {
    const events: string[] = [];
    const { repository, media } = dependencies(events);
    const onDeleted = jest.fn();
    const alert = jest.spyOn(Alert, 'alert');
    const view = await render(
      <DeleteRecordButton
        media={media}
        onDeleted={onDeleted}
        recordId="record-1"
        repository={repository}
      />,
    );

    await fireEvent.press(view.getByRole('button', { name: '删除' }));
    await act(async () => {
      alert.mock.calls[0]?.[2]?.find((button) => button.text === '删除')?.onPress?.();
      await Promise.resolve();
      await Promise.resolve();
    });

    expect(events).toEqual(['database-delete', 'media-remove']);
    expect(media.remove).toHaveBeenCalledWith([
      'file:///documents/media/photo.jpg',
      'file:///documents/media/photo-thumb.jpg',
    ]);
    expect(onDeleted).toHaveBeenCalledTimes(1);
  });

  test('treats post-delete media failure as cleanup pending, not a false delete failure', async () => {
    const cleanupError = new Error('media is locked');
    const { repository, media } = dependencies();
    media.remove.mockRejectedValue(cleanupError);
    const onCleanupPending = jest.fn();
    const onDeleted = jest.fn();
    const alert = jest.spyOn(Alert, 'alert');
    const view = await render(
      <DeleteRecordButton
        media={media}
        onCleanupPending={onCleanupPending}
        onDeleted={onDeleted}
        recordId="record-1"
        repository={repository}
      />,
    );

    await fireEvent.press(view.getByRole('button', { name: '删除' }));
    await act(async () => {
      alert.mock.calls[0]?.[2]?.find((button) => button.text === '删除')?.onPress?.();
      await Promise.resolve();
      await Promise.resolve();
    });

    expect(await view.findByText('记录已删除，媒体将在稍后清理')).toBeTruthy();
    expect(onCleanupPending).toHaveBeenCalledWith({
      scope: 'record',
      paths: [
        'file:///documents/media/photo.jpg',
        'file:///documents/media/photo-thumb.jpg',
      ],
      cause: cleanupError,
    });
    expect(onDeleted).toHaveBeenCalledTimes(1);
    expect(view.queryByText(/删除失败/)).toBeNull();
  });

  test('reports the database stage and does not touch media when deletion fails', async () => {
    const { repository, media } = dependencies();
    repository.delete.mockRejectedValue(new Error('database is locked'));
    const alert = jest.spyOn(Alert, 'alert');
    const view = await render(
      <DeleteRecordButton media={media} recordId="record-1" repository={repository} />,
    );

    await fireEvent.press(view.getByRole('button', { name: '删除' }));
    await act(async () => {
      alert.mock.calls[0]?.[2]?.find((button) => button.text === '删除')?.onPress?.();
      await Promise.resolve();
      await Promise.resolve();
    });

    await waitFor(() => expect(
      view.getByText('删除失败（数据库阶段）：database is locked，请重试'),
    ).toBeTruthy());
    expect(media.remove).not.toHaveBeenCalled();
  });
});

function dependencies(events: string[] = []) {
  const repository: jest.Mocked<RecordRepository> = {
    create: jest.fn(),
    update: jest.fn(),
    get: jest.fn(),
    list: jest.fn(),
    listPage: jest.fn(),
    withTransaction: jest.fn(),
    delete: jest.fn<ReturnType<RecordRepository['delete']>, Parameters<RecordRepository['delete']>>(
      async () => {
      events.push('database-delete');
        return [{
        id: 'attachment-1',
        recordId: 'record-1',
        mediaType: 'image',
        filePath: 'file:///documents/media/photo.jpg',
        thumbnailPath: 'file:///documents/media/photo-thumb.jpg',
        createdAt: '2026-08-01T08:00:00.000Z',
        }];
      },
    ),
  };
  const media: jest.Mocked<MediaService> = {
    stage: jest.fn(),
    commit: jest.fn(),
    rollback: jest.fn(),
    removeOrphans: jest.fn(),
    remove: jest.fn<Promise<void>, [string[]]>(async () => {
      events.push('media-remove');
    }),
  };
  return { media, repository };
}
