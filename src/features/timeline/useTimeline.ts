import { useCallback, useEffect, useRef, useState } from 'react';

import type { RecordRepository } from '../../data/repositories';
import type { RecordType, TimelineRecord } from '../../domain/types';

export interface TimelineState {
  records: TimelineRecord[];
  selectedTypes: RecordType[];
  loading: boolean;
  error: string | null;
  setSelectedTypes(types: RecordType[]): void;
  reload(): Promise<void>;
}

const loadErrorMessage = '无法读取记录，请重试';

export function useTimeline(repository: RecordRepository): TimelineState {
  const [records, setRecords] = useState<TimelineRecord[]>([]);
  const [selectedTypes, setSelectedTypesState] = useState<RecordType[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const requestVersion = useRef(0);

  const setSelectedTypes = useCallback((types: RecordType[]) => {
    setSelectedTypesState([...types]);
  }, []);

  const reload = useCallback(async () => {
    const version = requestVersion.current + 1;
    requestVersion.current = version;
    setLoading(true);
    setError(null);

    try {
      const nextRecords = await repository.list({ types: selectedTypes });
      if (requestVersion.current === version) {
        setRecords(nextRecords);
      }
    } catch (reason) {
      const loadError = reason instanceof Error ? reason : new Error(loadErrorMessage);
      if (requestVersion.current === version) {
        setError(loadErrorMessage);
      }
      throw loadError;
    } finally {
      if (requestVersion.current === version) {
        setLoading(false);
      }
    }
  }, [repository, selectedTypes]);

  useEffect(() => {
    void reload().catch(() => undefined);
  }, [reload]);

  return { records, selectedTypes, loading, error, setSelectedTypes, reload };
}
