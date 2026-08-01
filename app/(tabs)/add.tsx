import { useRouter, type Href } from 'expo-router';

import { RecordTypePicker } from '../../src/features/records/RecordTypePicker';

export default function AddScreen() {
  const router = useRouter();

  return (
    <RecordTypePicker onSelect={(type) => {
      router.push(`/record/new?type=${type}` as Href);
    }} />
  );
}
