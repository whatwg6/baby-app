import { createContext, useContext, type ReactNode } from 'react';

import type { RecordRepository } from '../../data/repositories';

const RecordRepositoryContext = createContext<RecordRepository | null>(null);

export function RecordRepositoryProvider({
  repository,
  children,
}: {
  repository: RecordRepository;
  children: ReactNode;
}) {
  return (
    <RecordRepositoryContext.Provider value={repository}>
      {children}
    </RecordRepositoryContext.Provider>
  );
}

export function useRecordRepository(): RecordRepository {
  const repository = useContext(RecordRepositoryContext);
  if (repository === null) {
    throw new Error('useRecordRepository must be used within RecordRepositoryProvider.');
  }
  return repository;
}
