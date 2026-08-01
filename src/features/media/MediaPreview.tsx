import { useEffect, useState } from 'react';
import { Image, Pressable, StyleSheet, Text, View } from 'react-native';

import type { MediaType } from '../../domain/types';
import { colors, radius, spacing } from '../../ui/theme';

export function MediaPreview({
  uri,
  mediaType,
  onRemove,
  accessibilityLabel = '媒体预览',
}: {
  uri: string;
  mediaType: MediaType;
  onRemove?(): void;
  accessibilityLabel?: string;
}) {
  const [unavailable, setUnavailable] = useState(uri.trim().length === 0);

  useEffect(() => {
    setUnavailable(uri.trim().length === 0);
  }, [uri]);

  return (
    <View style={styles.container}>
      {unavailable ? (
        <View accessibilityLabel="媒体文件不可用" style={styles.placeholder}>
          <Text style={styles.placeholderText}>媒体文件不可用</Text>
        </View>
      ) : mediaType === 'video' ? (
        <View accessibilityLabel="视频媒体" style={styles.placeholder}>
          <Text style={styles.placeholderText}>视频媒体</Text>
        </View>
      ) : (
        <Image
          accessibilityLabel={accessibilityLabel}
          onError={() => setUnavailable(true)}
          source={{ uri }}
          style={styles.image}
        />
      )}
      {onRemove === undefined ? null : (
        <Pressable accessibilityRole="button" onPress={onRemove}>
          <Text style={styles.remove}>移除</Text>
        </Pressable>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { alignItems: 'center', gap: spacing.xs },
  image: { borderRadius: radius.sm, height: 104, width: 104 },
  placeholder: {
    alignItems: 'center',
    backgroundColor: colors.card,
    borderRadius: radius.sm,
    height: 104,
    justifyContent: 'center',
    padding: spacing.sm,
    width: 104,
  },
  placeholderText: { color: colors.muted, fontSize: 13, textAlign: 'center' },
  remove: { color: colors.danger, fontSize: 13 },
});
