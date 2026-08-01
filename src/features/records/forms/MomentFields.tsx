import { StyleSheet, Text, View } from 'react-native';

import { colors, spacing } from '../../../ui/theme';

export function MomentFields() {
  return (
    <View style={styles.container}>
      <Text style={styles.hint}>写下这一刻，或稍后添加媒体。</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { gap: spacing.xs },
  hint: { color: colors.muted, fontSize: 14 },
});
