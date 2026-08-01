import { useEffect } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useRouter } from 'expo-router';

import { useBaby } from '../src/features/baby/useBaby';
import { colors, spacing } from '../src/ui/theme';

export default function Index() {
  const { baby, error, loading, reload } = useBaby();
  const router = useRouter();

  useEffect(() => {
    if (!loading && error === null) {
      router.replace(baby === null ? '/baby/setup' : '/(tabs)/timeline');
    }
  }, [baby, error, loading, router]);

  if (error !== null) {
    return (
      <View style={styles.container}>
        <Text style={styles.text}>暂时无法读取宝宝资料</Text>
        <Pressable accessibilityRole="button" onPress={() => void reload().catch(() => undefined)}>
          <Text style={styles.retry}>重试</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Text style={styles.text}>正在打开成长时间轴…</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    backgroundColor: colors.background,
    flex: 1,
    justifyContent: 'center',
    padding: spacing.lg,
  },
  text: { color: colors.muted, fontSize: 15 },
  retry: { color: colors.accent, fontSize: 16, fontWeight: '700', marginTop: spacing.md },
});
