import { useEffect, useRef, useState } from 'react';
import { StyleSheet, Text, TextInput, View } from 'react-native';

import type { GrowthDetails } from '../../../domain/types';
import { colors, radius, spacing } from '../../../ui/theme';

type GrowthField = keyof GrowthDetails;

export function GrowthFields({
  initialValue,
  resetKey,
  onChange,
}: {
  initialValue: GrowthDetails;
  resetKey: string;
  onChange(details: GrowthDetails): void;
}) {
  const [values, setValues] = useState(() => toInputValues(initialValue));
  const valuesRef = useRef(values);
  const previousResetKey = useRef(resetKey);

  useEffect(() => {
    if (previousResetKey.current === resetKey) {
      return;
    }
    previousResetKey.current = resetKey;
    const nextValues = toInputValues(initialValue);
    valuesRef.current = nextValues;
    setValues(nextValues);
  }, [initialValue, resetKey]);

  const update = (field: GrowthField, nextValue: string) => {
    const nextValues = { ...valuesRef.current, [field]: nextValue };
    valuesRef.current = nextValues;
    setValues(nextValues);
    onChange(toDetails(nextValues));
  };

  return (
    <View style={styles.container}>
      <NumberField
        accessibilityLabel="身高（cm）"
        label="身高（cm）"
        value={values.heightCm}
        onChangeText={(heightCm) => update('heightCm', heightCm)}
      />
      <NumberField
        accessibilityLabel="体重（kg）"
        label="体重（kg）"
        value={values.weightKg}
        onChangeText={(weightKg) => update('weightKg', weightKg)}
      />
      <NumberField
        accessibilityLabel="头围（cm）"
        label="头围（cm）"
        value={values.headCm}
        onChangeText={(headCm) => update('headCm', headCm)}
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

function toInputValues(details: GrowthDetails): Record<GrowthField, string> {
  return {
    heightCm: toInputValue(details.heightCm),
    weightKg: toInputValue(details.weightKg),
    headCm: toInputValue(details.headCm),
  };
}

function toInputValue(value: number | null): string {
  return value === null ? '' : String(value);
}

function toNullableNumber(value: string): number | null {
  const trimmed = value.trim();
  return trimmed === '' ? null : Number(trimmed);
}

function toDetails(values: Record<GrowthField, string>): GrowthDetails {
  return {
    heightCm: toNullableNumber(values.heightCm),
    weightKg: toNullableNumber(values.weightKg),
    headCm: toNullableNumber(values.headCm),
  };
}

const styles = StyleSheet.create({
  container: { gap: spacing.md },
  label: { color: colors.text, fontSize: 15, fontWeight: '600', marginBottom: spacing.sm },
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
