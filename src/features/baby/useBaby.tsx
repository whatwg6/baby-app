import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';

import type { BabyRepository } from '../../data/repositories';
import type { Baby, BabyInput } from '../../domain/types';

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

  const save = useCallback(async (input: BabyInput) => {
    const saved = await repository.save(input);
    setBaby(saved);
    return saved;
  }, [repository]);

  return { baby, loading, error, save, reload };
}
