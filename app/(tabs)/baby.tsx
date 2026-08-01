import { useEffect } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useRouter } from 'expo-router';

import BabyForm from '../../src/features/baby/BabyForm';
import BabyHeader from '../../src/features/baby/BabyHeader';
import { useBaby } from '../../src/features/baby/useBaby';
import { colors, spacing } from '../../src/ui/theme';

export default function BabyScreen() {
  const { baby, cleanupWarning, error, loading, reload, save } = useBaby();
  const router = useRouter();

  useEffect(() => {
    if (!loading && error === null && baby === null) {
      router.replace('/baby/setup');
    }
  }, [baby, error, loading, router]);

  return (
    <View style={styles.container}>
      <Text style={styles.title}>宝宝资料</Text>
      {loading ? <Text style={styles.status}>正在读取资料…</Text> : null}
      {error === null ? null : (
        <View style={styles.errorState}>
          <Text style={styles.status}>暂时无法读取宝宝资料</Text>
          <Pressable accessibilityRole="button" onPress={() => void reload().catch(() => undefined)}>
            <Text style={styles.retry}>重试</Text>
          </Pressable>
        </View>
      )}
      {cleanupWarning === null ? null : (
        <Text style={styles.warning}>{cleanupWarning}</Text>
      )}
      {baby === null ? null : (
        <View style={styles.content}>
          <BabyHeader baby={baby} />
          <BabyForm initialValue={baby} onSave={save} />
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: colors.background,
    flex: 1,
    padding: spacing.lg,
  },
  title: {
    color: colors.text,
    fontSize: 20,
    fontWeight: '600',
  },
  status: { color: colors.muted, marginTop: spacing.lg },
  errorState: { gap: spacing.md },
  retry: { color: colors.accent, fontSize: 16, fontWeight: '700' },
  warning: { color: colors.muted, marginTop: spacing.md },
  content: { gap: spacing.xl, marginTop: spacing.lg },
});
