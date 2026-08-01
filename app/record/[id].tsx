import { useLocalSearchParams, useRouter, type Href } from 'expo-router';

import { useAppServices } from '../../src/app/AppProvider';
import { DELETE_CLEANUP_PENDING_MESSAGE } from '../../src/features/records/DeleteRecordButton';
import RecordDetail from '../../src/features/records/RecordDetail';

export default function RecordDetailRoute() {
  const { media, records: repository, reportCleanupWarning } = useAppServices();
  const router = useRouter();
  const { id } = useLocalSearchParams<{ id?: string | string[] }>();
  const recordId = typeof id === 'string' ? id : '';

  return (
    <RecordDetail
      media={media}
      onCleanupPending={() => reportCleanupWarning(DELETE_CLEANUP_PENDING_MESSAGE)}
      repository={repository}
      recordId={recordId}
      onEdit={(target) => router.push(target as Href)}
      onDelete={() => router.replace('/(tabs)/timeline')}
    />
  );
}
