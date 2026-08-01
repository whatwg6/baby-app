import { useLocalSearchParams, useRouter, type Href } from 'expo-router';

import type { RecordType } from '../../src/domain/types';
import { RecordEditor, toNewRecordInput } from '../../src/features/records/RecordEditor';
import { useRecordRepository } from '../../src/features/records/RecordRepositoryProvider';
import { RecordTypePicker } from '../../src/features/records/RecordTypePicker';

export default function NewRecordRoute() {
  const repository = useRecordRepository();
  const router = useRouter();
  const { type: typeParam } = useLocalSearchParams<{ type?: string | string[] }>();
  const type = isRecordType(typeParam) ? typeParam : null;

  if (type === null) {
    return (
      <RecordTypePicker onSelect={(selectedType) => {
        router.push(`/record/new?type=${selectedType}` as Href);
      }} />
    );
  }

  return (
    <RecordEditor
      onSubmit={async (draft) => {
        await repository.create(toNewRecordInput(draft));
        router.replace('/(tabs)/timeline' as Href);
      }}
      type={type}
    />
  );
}

function isRecordType(value: string | string[] | undefined): value is RecordType {
  return typeof value === 'string' && ['moment', 'growth', 'activity', 'milestone'].includes(value);
}
