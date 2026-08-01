import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';

import type { BabyRepository } from '../../data/repositories';
import type { Baby, BabyInput } from '../../domain/types';
import {
  mediaService,
  type MediaService,
  type StagedMedia,
} from '../media/mediaService';
import type { PickedAvatar } from './BabyForm';

const BabyRepositoryContext = createContext<BabyRepository | null>(null);

export function BabyRepositoryProvider({
  repository,
  children,
}: {
  repository: BabyRepository;
  children: ReactNode;
}) {
  return (
    <BabyRepositoryContext.Provider value={repository}>
      {children}
    </BabyRepositoryContext.Provider>
  );
}

export function useBaby() {
  const repository = useContext(BabyRepositoryContext);
  const [baby, setBaby] = useState<Baby | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  if (repository === null) {
    throw new Error('useBaby must be used within BabyRepositoryProvider.');
  }

  const reload = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setBaby(await repository.get());
    } catch (reason) {
      const loadError = reason instanceof Error ? reason : new Error('Unable to load baby profile.');
      setError(loadError);
      throw loadError;
    } finally {
      setLoading(false);
    }
  }, [repository]);

  useEffect(() => {
    void reload().catch(() => undefined);
  }, [reload]);

  const save = useCallback(async (input: BabyInput, pickedAvatar?: PickedAvatar) => {
    const saved = await saveBabyWithAvatar(input, pickedAvatar, {
      babies: repository,
      media: mediaService,
    });
    setBaby(saved);
    return saved;
  }, [repository]);

  return { baby, loading, error, save, reload };
}

export async function saveBabyWithAvatar(
  input: BabyInput,
  pickedAvatar: PickedAvatar | undefined,
  dependencies: { babies: BabyRepository; media: MediaService },
): Promise<Baby> {
  const previous = await dependencies.babies.get();
  if (pickedAvatar === undefined) {
    const saved = await dependencies.babies.save(input);
    if (previous?.avatarPath !== null && previous?.avatarPath !== undefined &&
        previous.avatarPath !== saved.avatarPath) {
      await dependencies.media.remove([previous.avatarPath]);
    }
    return saved;
  }

  const staged: StagedMedia = await dependencies.media.stage({
    uri: pickedAvatar.sourceUri,
    mediaType: 'image',
  });
  const committed = await dependencies.media.commit(staged).catch((error: unknown) => (
    cleanupAndRethrow(error, [() => dependencies.media.rollback(staged)])
  ));
  const saved: Baby = await dependencies.babies
    .save({ ...input, avatarPath: committed.filePath })
    .catch((error: unknown) => cleanupAndRethrow(error, [
      () => dependencies.media.rollback(staged),
      () => dependencies.media.remove([
        committed.filePath,
        ...(committed.thumbnailPath === null ? [] : [committed.thumbnailPath]),
      ]),
    ]));

  const pathsToRemove = [
    ...(committed.thumbnailPath === null ? [] : [committed.thumbnailPath]),
    ...(previous?.avatarPath === null || previous?.avatarPath === undefined ||
      previous.avatarPath === saved.avatarPath ? [] : [previous.avatarPath]),
  ];
  if (pathsToRemove.length > 0) {
    await dependencies.media.remove(pathsToRemove);
  }
  return saved;
}

async function cleanupAndRethrow(
  primaryError: unknown,
  tasks: Array<() => Promise<void>>,
): Promise<never> {
  const results = await Promise.allSettled(tasks.map((task) => task()));
  const cleanupErrors = results.flatMap((result) => (
    result.status === 'rejected' ? [result.reason] : []
  ));
  if (cleanupErrors.length > 0) {
    throw new AggregateError([primaryError, ...cleanupErrors], '头像保存与媒体清理均失败');
  }
  throw primaryError;
}
