import {
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useRouter } from 'expo-router';

import BabyForm from '../../src/features/baby/BabyForm';
import { useBaby } from '../../src/features/baby/useBaby';
import { colors, spacing } from '../../src/ui/theme';

export default function BabySetupScreen() {
  const { cleanupWarning, error, loading, reload, save } = useBaby();
  const router = useRouter();

  if (loading) {
    return (
      <View style={styles.stateContainer}>
        <Text style={styles.subheading}>正在准备资料…</Text>
      </View>
    );
  }

  if (error !== null) {
    return (
      <View style={styles.stateContainer}>
        <Text style={styles.subheading}>暂时无法读取宝宝资料</Text>
        <Pressable accessibilityRole="button" onPress={() => void reload().catch(() => undefined)}>
          <Text style={styles.retry}>重试</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      style={styles.keyboardAvoiding}
      testID="baby-setup-keyboard-avoiding"
    >
      <ScrollView
        contentContainerStyle={styles.container}
        keyboardShouldPersistTaps="handled"
        testID="baby-setup-scroll"
      >
        <Text style={styles.heading}>先认识一下宝宝</Text>
        <Text style={styles.subheading}>填写姓名和生日，就可以开始记录成长。</Text>
        {cleanupWarning === null ? null : (
          <Text style={styles.warning}>{cleanupWarning}</Text>
        )}
        <BabyForm
          onSave={async (input, pickedAvatar) => {
            await save(input, pickedAvatar);
            router.replace('/(tabs)/timeline');
          }}
        />
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  keyboardAvoiding: { backgroundColor: colors.background, flex: 1 },
  container: {
    flexGrow: 1,
    padding: spacing.lg,
  },
  stateContainer: {
    backgroundColor: colors.background,
    flex: 1,
    padding: spacing.lg,
  },
  heading: { color: colors.text, fontSize: 26, fontWeight: '700', marginTop: spacing.xl },
  subheading: { color: colors.muted, fontSize: 15, lineHeight: 22, marginBottom: spacing.xl, marginTop: spacing.sm },
  retry: { color: colors.accent, fontSize: 16, fontWeight: '700' },
  warning: { color: colors.muted, marginBottom: spacing.md },
});
