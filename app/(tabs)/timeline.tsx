import { Pressable, StyleSheet, Text, View } from 'react-native';

import { colors, radius, spacing } from '../../src/ui/theme';

export default function TimelineScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>还没有成长记录</Text>
      <Pressable style={styles.action} accessibilityRole="button">
        <Text style={styles.actionText}>记录第一个瞬间</Text>
      </Pressable>
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
  title: {
    color: colors.muted,
    fontSize: 18,
    marginBottom: spacing.md,
  },
  action: {
    backgroundColor: colors.accent,
    borderRadius: radius.md,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.md,
  },
  actionText: {
    color: colors.card,
    fontSize: 16,
    fontWeight: '600',
  },
});
