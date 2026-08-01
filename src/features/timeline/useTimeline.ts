import { useCallback, useEffect, useRef, useState } from 'react';

import type { RecordPageCursor, RecordRepository } from '../../data/repositories';
import type { RecordType, TimelineRecord } from '../../domain/types';

export interface TimelineState {
  records: TimelineRecord[];
  selectedTypes: RecordType[];
  loading: boolean;
  loadingMore: boolean;
  error: string | null;
  loadMoreError: string | null;
  setSelectedTypes(types: RecordType[]): void;
  loadMore(): Promise<void>;
  reload(): Promise<void>;
  retry(): Promise<void>;
}

const loadErrorMessage = '无法读取记录，请重试';
const timelinePageSize = 20;

type FailedRequest = 'initial' | 'more' | null;

export function useTimeline(repository: RecordRepository): TimelineState {
  const [records, setRecords] = useState<TimelineRecord[]>([]);
  const [selectedTypes, setSelectedTypesState] = useState<RecordType[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loadMoreError, setLoadMoreError] = useState<string | null>(null);
  const chainVersion = useRef(0);
  const nextCursorRef = useRef<RecordPageCursor | null>(null);
  const loadMoreInFlight = useRef(false);
  const failedRequest = useRef<FailedRequest>(null);

  const setSelectedTypes = useCallback((types: RecordType[]) => {
    chainVersion.current += 1;
    nextCursorRef.current = null;
    loadMoreInFlight.current = false;
    failedRequest.current = null;
    setRecords([]);
    setError(null);
    setLoadMoreError(null);
    setLoading(true);
    setLoadingMore(false);
    setSelectedTypesState([...types]);
  }, []);

  const reload = useCallback(async () => {
    const version = chainVersion.current + 1;
    chainVersion.current = version;
    nextCursorRef.current = null;
    loadMoreInFlight.current = false;
    failedRequest.current = null;
    setLoading(true);
    setLoadingMore(false);
    setError(null);
    setLoadMoreError(null);

    try {
      const page = await repository.listPage({
        types: selectedTypes,
        cursor: null,
        limit: timelinePageSize,
      });
      if (chainVersion.current === version) {
        setRecords(page.records);
        nextCursorRef.current = page.nextCursor;
      }
    } catch (reason) {
      const loadError = reason instanceof Error ? reason : new Error(loadErrorMessage);
      if (chainVersion.current === version) {
        failedRequest.current = 'initial';
        setError(loadErrorMessage);
      }
      throw loadError;
    } finally {
      if (chainVersion.current === version) {
        setLoading(false);
      }
    }
  }, [repository, selectedTypes]);

  const loadMore = useCallback(async () => {
    const cursor = nextCursorRef.current;
    if (cursor === null || loadMoreInFlight.current) {
      return;
    }

    const version = chainVersion.current;
    loadMoreInFlight.current = true;
    failedRequest.current = null;
    setLoadingMore(true);
    setError(null);
    setLoadMoreError(null);

    try {
      const page = await repository.listPage({
        types: selectedTypes,
        cursor,
        limit: timelinePageSize,
      });
      if (chainVersion.current === version) {
        setRecords((current) => appendUniqueRecords(current, page.records));
        nextCursorRef.current = page.nextCursor;
      }
    } catch (reason) {
      const loadError = reason instanceof Error ? reason : new Error(loadErrorMessage);
      if (chainVersion.current === version) {
        failedRequest.current = 'more';
        setLoadMoreError(loadErrorMessage);
      }
      throw loadError;
    } finally {
      if (chainVersion.current === version) {
        loadMoreInFlight.current = false;
        setLoadingMore(false);
      }
    }
  }, [repository, selectedTypes]);

  const retry = useCallback(
    () => (failedRequest.current === 'more' ? loadMore() : reload()),
    [loadMore, reload],
  );

  useEffect(() => {
    void reload().catch(() => undefined);
  }, [reload]);

  return {
    records,
    selectedTypes,
    loading,
    loadingMore,
    error,
    loadMoreError,
    setSelectedTypes,
    loadMore,
    reload,
    retry,
  };
}

function appendUniqueRecords(
  current: TimelineRecord[],
  next: TimelineRecord[],
): TimelineRecord[] {
  const existingIds = new Set(current.map((record) => record.id));
  return [
    ...current,
    ...next.filter((record) => !existingIds.has(record.id)),
  ];
}
