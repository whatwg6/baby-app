import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useRouter, type Href } from 'expo-router';

import TimelineFeatureScreen from '../../src/features/timeline/TimelineScreen';
import { useBaby } from '../../src/features/baby/useBaby';
import { useRecordRepository } from '../../src/features/records/RecordRepositoryProvider';
import { colors, spacing } from '../../src/ui/theme';

export default function TimelineScreen() {
  const repository = useRecordRepository();
  const router = useRouter();
  const { baby, error, loading, reload } = useBaby();

  if (loading) {
    return (
      <View style={styles.container}>
        <Text style={styles.status}>正在读取宝宝资料…</Text>
      </View>
    );
  }

  if (error !== null) {
    return (
      <View style={styles.container}>
        <Text style={styles.status}>暂时无法读取宝宝资料</Text>
        <Pressable accessibilityRole="button" onPress={() => void reload().catch(() => undefined)}>
          <Text style={styles.retry}>重试</Text>
        </Pressable>
      </View>
    );
  }

  if (baby === null) {
    return (
      <View style={styles.container}>
        <Text style={styles.status}>请先完成宝宝资料</Text>
      </View>
    );
  }

  return (
    <TimelineFeatureScreen
      repository={repository}
      baby={baby}
      onAddPress={() => router.push('/(tabs)/add' as Href)}
      onRecordPress={(record) => router.push(`/record/${record.id}` as Href)}
    />
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    backgroundColor: colors.background,
    flex: 1,
    gap: spacing.md,
    justifyContent: 'center',
    padding: spacing.lg,
  },
  status: { color: colors.muted, fontSize: 16 },
  retry: { color: colors.accent, fontSize: 16, fontWeight: '700' },
});
