import { useEffect, useState } from 'react';
import { Image, StyleSheet, Text, View } from 'react-native';

import { calculateAgeLabel } from '../../domain/date';
import type { Baby } from '../../domain/types';
import { colors, radius, spacing } from '../../ui/theme';

export default function BabyHeader({ baby, now = new Date() }: { baby: Baby; now?: Date }) {
  const initials = baby.name.trim().slice(0, 1) || '宝';
  const [avatarUnavailable, setAvatarUnavailable] = useState(baby.avatarPath === null);

  useEffect(() => {
    setAvatarUnavailable(baby.avatarPath === null);
  }, [baby.avatarPath]);

  return (
    <View style={styles.container}>
      {avatarUnavailable || baby.avatarPath === null ? (
        <View accessibilityLabel="宝宝头像" style={styles.placeholderAvatar}>
          <Text style={styles.initials}>{initials}</Text>
        </View>
      ) : (
        <Image
          accessibilityLabel="宝宝头像"
          onError={() => setAvatarUnavailable(true)}
          source={{ uri: baby.avatarPath }}
          style={styles.avatar}
        />
      )}
      <View>
        <Text style={styles.name}>{baby.name}</Text>
        <Text style={styles.age}>{calculateAgeLabel(baby.birthDate, now)}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { alignItems: 'center', flexDirection: 'row', gap: spacing.md },
  avatar: { borderRadius: radius.lg, height: 64, width: 64 },
  placeholderAvatar: {
    alignItems: 'center',
    backgroundColor: colors.accent,
    borderRadius: radius.lg,
    height: 64,
    justifyContent: 'center',
    width: 64,
  },
  initials: { color: colors.card, fontSize: 26, fontWeight: '700' },
  name: { color: colors.text, fontSize: 22, fontWeight: '700' },
  age: { color: colors.muted, fontSize: 15, marginTop: spacing.xs },
});
