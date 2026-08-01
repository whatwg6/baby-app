import { useEffect, useState } from 'react';
import {
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';

import { parseBabyInput } from '../../domain/validation';
import type { BabyInput } from '../../domain/types';
import { colors, radius, spacing } from '../../ui/theme';

type BabyFormProps = {
  initialValue?: BabyInput;
  now?: Date;
  onSave: (input: BabyInput) => void | Promise<unknown>;
};

type FormValue = {
  name: string;
  birthDate: string;
  sex: BabyInput['sex'];
  avatarPath: string;
};

type FormErrors = Partial<Record<'name' | 'birthDate' | 'save', string>>;

function toFormValue(initialValue?: BabyInput): FormValue {
  return {
    name: initialValue?.name ?? '',
    birthDate: initialValue?.birthDate ?? '',
    sex: initialValue?.sex ?? null,
    avatarPath: initialValue?.avatarPath ?? '',
  };
}

function isValidLocalDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }

  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(year, month - 1, day);
  return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day;
}

function getFieldErrors(value: FormValue, now: Date): FormErrors {
  const errors: FormErrors = {};
  if (value.name.trim() === '') {
    errors.name = '请填写宝宝姓名';
  }

  try {
    parseBabyInput({
      name: value.name,
      birthDate: value.birthDate,
      sex: value.sex,
      avatarPath: value.avatarPath.trim() || null,
    }, now);
  } catch (error) {
    if (value.birthDate.trim() === '') {
      errors.birthDate = '请填写出生日期';
    } else if (!isValidLocalDate(value.birthDate)) {
      errors.birthDate = '请输入有效的出生日期';
    } else if (error instanceof Error && error.message === 'Birth date cannot be in the future.') {
      errors.birthDate = '出生日期不能晚于今天';
    } else if (errors.name === undefined) {
      errors.birthDate = '请输入有效的出生日期';
    }
  }

  return errors;
}

export default function BabyForm({ initialValue, now = new Date(), onSave }: BabyFormProps) {
  const [value, setValue] = useState(() => toFormValue(initialValue));
  const [errors, setErrors] = useState<FormErrors>({});
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (initialValue !== undefined) {
      setValue(toFormValue(initialValue));
      setErrors({});
    }
  }, [initialValue]);

  const handleSave = () => {
    const fieldErrors = getFieldErrors(value, now);
    if (Object.keys(fieldErrors).length > 0) {
      setErrors(fieldErrors);
      return;
    }

    const input = parseBabyInput({
      name: value.name,
      birthDate: value.birthDate,
      sex: value.sex,
      avatarPath: value.avatarPath.trim() || null,
    }, now);

    setSaving(true);
    setErrors({});
    try {
      void Promise.resolve(onSave(input))
        .catch(() => {
          setErrors({ save: '保存失败，请稍后重试' });
        })
        .finally(() => {
          setSaving(false);
        });
    } catch {
      setErrors({ save: '保存失败，请稍后重试' });
      setSaving(false);
    }
  };

  return (
    <View style={styles.form}>
      <View>
        <Text style={styles.label}>宝宝姓名</Text>
        <TextInput
          accessibilityLabel="宝宝姓名"
          autoCapitalize="none"
          onChangeText={(name) => setValue((current) => ({ ...current, name }))}
          placeholder="例如：安安"
          style={styles.input}
          value={value.name}
        />
        {errors.name === undefined ? null : <Text style={styles.error}>{errors.name}</Text>}
      </View>

      <View>
        <Text style={styles.label}>出生日期</Text>
        <TextInput
          accessibilityLabel="出生日期"
          autoCapitalize="none"
          keyboardType="numbers-and-punctuation"
          onChangeText={(birthDate) => setValue((current) => ({ ...current, birthDate }))}
          placeholder="YYYY-MM-DD"
          style={styles.input}
          value={value.birthDate}
        />
        {errors.birthDate === undefined ? null : <Text style={styles.error}>{errors.birthDate}</Text>}
      </View>

      <View>
        <Text style={styles.label}>性别（可选）</Text>
        <View style={styles.sexOptions}>
          {([
            ['female', '女'],
            ['male', '男'],
            [null, '不填写'],
          ] as const).map(([sex, label]) => (
            <Pressable
              accessibilityRole="button"
              key={label}
              onPress={() => setValue((current) => ({ ...current, sex }))}
              style={[styles.sexOption, value.sex === sex && styles.sexOptionSelected]}
            >
              <Text style={[styles.sexOptionText, value.sex === sex && styles.sexOptionTextSelected]}>
                {label}
              </Text>
            </Pressable>
          ))}
        </View>
      </View>

      <View>
        <Text style={styles.label}>头像路径（可选）</Text>
        <TextInput
          accessibilityLabel="头像路径（可选）"
          autoCapitalize="none"
          onChangeText={(avatarPath) => setValue((current) => ({ ...current, avatarPath }))}
          placeholder="稍后可从相册选择"
          style={styles.input}
          value={value.avatarPath}
        />
      </View>

      {errors.save === undefined ? null : <Text style={styles.error}>{errors.save}</Text>}
      <Pressable
        accessibilityRole="button"
        disabled={saving}
        onPress={handleSave}
        style={[styles.saveButton, saving && styles.saveButtonDisabled]}
      >
        <Text style={styles.saveButtonText}>{saving ? '保存中…' : '保存'}</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  form: { gap: spacing.md },
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
  error: { color: colors.danger, fontSize: 13, marginTop: spacing.xs },
  sexOptions: { flexDirection: 'row', gap: spacing.sm },
  sexOption: {
    borderColor: colors.border,
    borderRadius: radius.md,
    borderWidth: 1,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  sexOptionSelected: { backgroundColor: colors.accent, borderColor: colors.accent },
  sexOptionText: { color: colors.muted, fontSize: 15 },
  sexOptionTextSelected: { color: colors.card, fontWeight: '600' },
  saveButton: {
    alignItems: 'center',
    backgroundColor: colors.accent,
    borderRadius: radius.md,
    marginTop: spacing.sm,
    padding: spacing.md,
  },
  saveButtonDisabled: { opacity: 0.6 },
  saveButtonText: { color: colors.card, fontSize: 16, fontWeight: '700' },
});
