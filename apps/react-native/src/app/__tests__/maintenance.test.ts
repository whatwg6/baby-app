import type { MediaService, StagedMedia } from '../../features/media/mediaService';
import {
  createMaintenanceAwareMediaService,
  createMaintenanceCoordinator,
} from '../maintenance';

function mediaDouble(): jest.Mocked<MediaService> {
  return {
    stage: jest.fn(async (_input: Parameters<MediaService['stage']>[0]): Promise<StagedMedia> => ({
      stagingPath: 'file:///documents/staging/new.jpg',
      finalPath: 'file:///documents/media/new.jpg',
      mediaType: 'image' as const,
      thumbnailStagingPath: null,
      thumbnailFinalPath: null,
    })),
    commit: jest.fn(async (staged: StagedMedia) => ({
      filePath: staged.finalPath,
      thumbnailPath: staged.thumbnailFinalPath,
    })),
    rollback: jest.fn(async (_staged: StagedMedia) => undefined),
    remove: jest.fn(async (_paths: string[]) => undefined),
    removeOrphans: jest.fn(async (_paths: string[]) => undefined),
  };
}

test('blocks new media staging and commit work for the full maintenance lease', async () => {
  const coordinator = createMaintenanceCoordinator();
  const raw = mediaDouble();
  const guarded = createMaintenanceAwareMediaService(raw, coordinator);
  const lease = coordinator.begin('clear');

  await expect(guarded.stage({ uri: 'file:///picker/new.jpg', mediaType: 'image' }))
    .rejects.toThrow('本地数据维护中');
  await expect(guarded.commit({
    stagingPath: 'file:///documents/staging/new.jpg',
    finalPath: 'file:///documents/media/new.jpg',
    mediaType: 'image',
    thumbnailStagingPath: null,
    thumbnailFinalPath: null,
  })).rejects.toThrow('本地数据维护中');
  expect(raw.stage).not.toHaveBeenCalled();
  expect(raw.commit).not.toHaveBeenCalled();

  lease.finish();
  await expect(guarded.stage({ uri: 'file:///picker/new.jpg', mediaType: 'image' }))
    .resolves.toMatchObject({ finalPath: 'file:///documents/media/new.jpg' });
});

test('retains a cleanup warning after the initiating maintenance owner finishes', () => {
  const coordinator = createMaintenanceCoordinator();
  const lease = coordinator.begin('clear');

  lease.finish({ warning: '旧媒体被系统锁定' });

  expect(coordinator.getSnapshot()).toEqual({
    active: false,
    operation: null,
    warning: '旧媒体被系统锁定',
  });
  coordinator.clearWarning();
  expect(coordinator.getSnapshot().warning).toBeNull();
});

test('publishes cleanup warnings outside maintenance so navigation cannot discard them', () => {
  const coordinator = createMaintenanceCoordinator();

  coordinator.publishWarning('记录已删除，媒体将在稍后清理');

  expect(coordinator.getSnapshot()).toEqual({
    active: false,
    operation: null,
    warning: '记录已删除，媒体将在稍后清理',
  });
});
