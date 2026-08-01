import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import type { MediaType, RecordDraftAttachment } from '../../domain/types';
import { colors, radius, spacing } from '../../ui/theme';

export function MediaPicker({
  allowedMedia,
  onPick,
}: {
  allowedMedia: readonly MediaType[];
  onPick(attachment: Extract<RecordDraftAttachment, { kind: 'picked' }>): void;
}) {
  const [error, setError] = useState<string | null>(null);
  const [picking, setPicking] = useState(false);
  const label = allowedMedia.includes('video') ? '选择图片或视频' : '选择图片';

  const pick = async () => {
    if (picking) {
      return;
    }
    setPicking(true);
    setError(null);
    try {
      // Load the native module only in direct response to a user action. This also keeps
      // screens renderable in non-native environments where the picker is unavailable.
      const ImagePicker = require('expo-image-picker') as typeof import('expo-image-picker');
      const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!permission.granted) {
        setError('请在系统设置中允许访问照片');
        return;
      }

      const result = await ImagePicker.launchImageLibraryAsync({
        allowsMultipleSelection: false,
        mediaTypes: allowedMedia.flatMap((type) => type === 'image' ? ['images' as const] : ['videos' as const]),
        quality: 1,
      });
      if (result.canceled) {
        return;
      }

      const asset = result.assets[0];
      const mediaType = asset?.type === 'video'
        ? 'video'
        : asset?.type === 'image'
          ? 'image'
          : null;
      if (asset === undefined || mediaType === null || !allowedMedia.includes(mediaType)) {
        setError('不支持此媒体格式');
        return;
      }
      onPick({ kind: 'picked', sourceUri: asset.uri, mediaType });
    } catch {
      setError('无法打开相册，请重试');
    } finally {
      setPicking(false);
    }
  };

  return (
    <View style={styles.container}>
      <Pressable
        accessibilityRole="button"
        disabled={picking}
        onPress={() => void pick()}
        style={[styles.button, picking && styles.disabled]}
      >
        <Text style={styles.buttonText}>{picking ? '正在打开相册…' : label}</Text>
      </Pressable>
      {error === null ? null : <Text style={styles.error}>{error}</Text>}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { alignItems: 'flex-start', gap: spacing.xs },
  button: {
    borderColor: colors.accent,
    borderRadius: radius.md,
    borderWidth: 1,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  disabled: { opacity: 0.6 },
  buttonText: { color: colors.accent, fontSize: 15, fontWeight: '600' },
  error: { color: colors.danger, fontSize: 13 },
});
