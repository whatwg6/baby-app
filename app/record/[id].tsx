import { useLocalSearchParams, useRouter, type Href } from 'expo-router';

import RecordDetail from '../../src/features/records/RecordDetail';
import { useRecordRepository } from '../../src/features/records/RecordRepositoryProvider';

export default function RecordDetailRoute() {
  const repository = useRecordRepository();
  const router = useRouter();
  const { id } = useLocalSearchParams<{ id?: string | string[] }>();
  const recordId = typeof id === 'string' ? id : '';

  return (
    <RecordDetail
      repository={repository}
      recordId={recordId}
      onEdit={(target) => router.push(target as Href)}
    />
  );
}
