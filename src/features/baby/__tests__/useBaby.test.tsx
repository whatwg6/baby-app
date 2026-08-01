import { render, waitFor } from '@testing-library/react-native';
import { useEffect } from 'react';
import { Text } from 'react-native';

import type { BabyInput } from '../../../domain/types';
import type { MediaService, StagedMedia } from '../../media/mediaService';
import { MemoryBabyRepository } from '../../../test/memoryRepositories';
import { BabyRepositoryProvider, saveBabyWithAvatar, useBaby } from '../useBaby';

const input: BabyInput = {
  name: '安安',
  birthDate: '2025-06-15',
  sex: 'female',
  avatarPath: null,
};

test('loads and saves the baby profile through the supplied repository', async () => {
  const repository = new MemoryBabyRepository();

  function ProfileProbe() {
    const { baby, loading, save } = useBaby();

    useEffect(() => {
      if (!loading && baby === null) {
        void save(input);
      }
    }, [baby, loading, save]);

    return <Text>{loading ? '加载中' : baby?.name ?? '暂无资料'}</Text>;
  }

  const view = await render(
    <BabyRepositoryProvider repository={repository}>
      <ProfileProbe />
    </BabyRepositoryProvider>,
  );

  await waitFor(() => expect(view.getByText('安安')).toBeTruthy());
  await expect(repository.get()).resolves.toMatchObject({ name: '安安' });
});

test('commits a picked avatar, saves its private path, then removes the old avatar', async () => {
  const events: string[] = [];
  const repository = new MemoryBabyRepository();
  await repository.save({ ...input, avatarPath: 'file:///documents/media/old.jpg' });
  const originalSave = repository.save.bind(repository);
  repository.save = jest.fn(async (babyInput) => {
    events.push('baby-save');
    return originalSave(babyInput);
  });
  const media = avatarMedia(events);

  const saved = await saveBabyWithAvatar(input, { sourceUri: 'file:///picker/new.jpg' }, {
    babies: repository,
    media,
  });

  expect(saved.avatarPath).toBe('file:///documents/media/new.jpg');
  expect(events).toEqual(['avatar-stage', 'avatar-commit', 'baby-save', 'avatar-remove']);
  expect(media.remove).toHaveBeenLastCalledWith([
    'file:///documents/media/new-thumb.jpg',
    'file:///documents/media/old.jpg',
  ]);
});

test('removes the new avatar and preserves the old one when saving fails', async () => {
  const events: string[] = [];
  const repository = new MemoryBabyRepository();
  await repository.save({ ...input, avatarPath: 'file:///documents/media/old.jpg' });
  repository.save = jest.fn(async () => {
    events.push('baby-save');
    throw new Error('database failed');
  });
  const media = avatarMedia(events);

  await expect(saveBabyWithAvatar(input, { sourceUri: 'file:///picker/new.jpg' }, {
    babies: repository,
    media,
  })).rejects.toThrow('database failed');

  expect(media.remove).toHaveBeenCalledWith([
    'file:///documents/media/new.jpg',
    'file:///documents/media/new-thumb.jpg',
  ]);
  await expect(repository.get()).resolves.toMatchObject({
    avatarPath: 'file:///documents/media/old.jpg',
  });
});

function avatarMedia(events: string[]): jest.Mocked<MediaService> {
  const staged: StagedMedia = {
    stagingPath: 'file:///documents/staging/new.jpg',
    finalPath: 'file:///documents/media/new.jpg',
    mediaType: 'image',
    thumbnailStagingPath: 'file:///documents/staging/new-thumb.jpg',
    thumbnailFinalPath: 'file:///documents/media/new-thumb.jpg',
  };
  return {
    stage: jest.fn(async (_input: { uri: string; mediaType: 'image' | 'video' }) => {
      events.push('avatar-stage');
      return staged;
    }),
    commit: jest.fn(async (_staged: StagedMedia) => {
      events.push('avatar-commit');
      return { filePath: staged.finalPath, thumbnailPath: staged.thumbnailFinalPath };
    }),
    rollback: jest.fn(async (_staged: StagedMedia) => undefined),
    remove: jest.fn(async (_paths: string[]) => {
      events.push('avatar-remove');
    }),
    removeOrphans: jest.fn(async (_referencedPaths: string[]) => undefined),
  };
}
