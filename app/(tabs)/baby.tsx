import { StyleSheet, Text, View } from 'react-native';

import { colors, spacing } from '../../src/ui/theme';

export default function BabyScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>宝宝资料</Text>
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
    color: colors.text,
    fontSize: 20,
    fontWeight: '600',
  },
});
