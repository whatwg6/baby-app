import { useEffect, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

import type { ActivityDetails, ActivityType } from '../../../domain/types';
import { colors, radius, spacing } from '../../../ui/theme';

export type EditableActivityDetails = Omit<ActivityDetails, 'activityType'> & {
  activityType: ActivityType | null;
};

const activityOptions: readonly [ActivityType, string][] = [
  ['feeding', '喂养'],
  ['sleep', '睡眠'],
  ['diaper', '尿布'],
];

export function ActivityFields({
  initialValue,
  resetKey,
  onChange,
}: {
  initialValue: EditableActivityDetails;
  resetKey: string;
  onChange(details: EditableActivityDetails): void;
}) {
  const [value, setValue] = useState(() => toFormValue(initialValue));
  const valueRef = useRef(value);
  const previousResetKey = useRef(resetKey);

  useEffect(() => {
    if (previousResetKey.current === resetKey) {
      return;
    }
    previousResetKey.current = resetKey;
    const nextValue = toFormValue(initialValue);
    valueRef.current = nextValue;
    setValue(nextValue);
  }, [initialValue, resetKey]);

  const update = (nextValue: FormValue) => {
    valueRef.current = nextValue;
    setValue(nextValue);
    onChange(toDetails(nextValue));
  };

  return (
    <View style={styles.container}>
      <View>
        <Text style={styles.label}>活动类型</Text>
        <Text style={styles.help}>选择类型即可保存；数量、时长和备注均可不填。</Text>
        <View style={styles.options}>
          {activityOptions.map(([activityType, label]) => (
            <Pressable
              accessibilityRole="button"
              accessibilityState={{ selected: value.activityType === activityType }}
              key={activityType}
              onPress={() => update({ ...valueRef.current, activityType })}
              style={[
                styles.option,
                value.activityType === activityType && styles.optionSelected,
              ]}
            >
              <Text style={[
                styles.optionText,
                value.activityType === activityType && styles.optionTextSelected,
              ]}>
                {label}
              </Text>
            </Pressable>
          ))}
        </View>
      </View>
      <NumberField
        accessibilityLabel="数量（可选）"
        label="数量（可选）"
        value={value.amount}
        onChangeText={(amount) => update({ ...valueRef.current, amount })}
      />
      <NumberField
        accessibilityLabel="时长（分钟，可选）"
        label="时长（分钟，可选）"
        value={value.durationMinutes}
        onChangeText={(durationMinutes) => update({ ...valueRef.current, durationMinutes })}
      />
    </View>
  );
}

function NumberField({
  accessibilityLabel,
  label,
  value,
  onChangeText,
}: {
  accessibilityLabel: string;
  label: string;
  value: string;
  onChangeText(value: string): void;
}) {
  return (
    <View>
      <Text style={styles.label}>{label}</Text>
      <TextInput
        accessibilityLabel={accessibilityLabel}
        keyboardType="decimal-pad"
        onChangeText={onChangeText}
        placeholder="可选"
        style={styles.input}
        value={value}
      />
    </View>
  );
}

type FormValue = {
  activityType: ActivityType | null;
  amount: string;
  durationMinutes: string;
};

function toFormValue(details: EditableActivityDetails): FormValue {
  return {
    activityType: details.activityType,
    amount: toInputValue(details.amount),
    durationMinutes: toInputValue(details.durationMinutes),
  };
}

function toInputValue(value: number | null): string {
  return value === null ? '' : String(value);
}

function toNullableNumber(value: string): number | null {
  const trimmed = value.trim();
  return trimmed === '' ? null : Number(trimmed);
}

function toDetails(value: FormValue): EditableActivityDetails {
  return {
    activityType: value.activityType,
    amount: toNullableNumber(value.amount),
    durationMinutes: toNullableNumber(value.durationMinutes),
  };
}

const styles = StyleSheet.create({
  container: { gap: spacing.md },
  label: { color: colors.text, fontSize: 15, fontWeight: '600', marginBottom: spacing.sm },
  help: { color: colors.muted, fontSize: 13, marginBottom: spacing.sm },
  options: { flexDirection: 'row', gap: spacing.sm },
  option: {
    borderColor: colors.border,
    borderRadius: radius.md,
    borderWidth: 1,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  optionSelected: { backgroundColor: colors.accent, borderColor: colors.accent },
  optionText: { color: colors.muted, fontSize: 15 },
  optionTextSelected: { color: colors.card, fontWeight: '600' },
  input: {
    backgroundColor: colors.card,
    borderColor: colors.border,
    borderRadius: radius.md,
    borderWidth: 1,
    color: colors.text,
    fontSize: 16,
    paddingHorizontal: spacing.md,
    paddingVertical: 12,
  },
});
