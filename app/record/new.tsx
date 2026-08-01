import { useLocalSearchParams, useRouter, type Href } from 'expo-router';

import { useAppServices } from '../../src/app/AppProvider';
import type { RecordType } from '../../src/domain/types';
import { saveRecordWithMedia } from '../../src/features/media/mediaService';
import { RecordEditor } from '../../src/features/records/RecordEditor';
import { RecordTypePicker } from '../../src/features/records/RecordTypePicker';

export default function NewRecordRoute() {
  const { media, records: repository } = useAppServices();
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
        await saveRecordWithMedia(draft, { records: repository, media });
        router.replace('/(tabs)/timeline' as Href);
      }}
      type={type}
    />
  );
}

function isRecordType(value: string | string[] | undefined): value is RecordType {
  return typeof value === 'string' && ['moment', 'growth', 'activity', 'milestone'].includes(value);
}
