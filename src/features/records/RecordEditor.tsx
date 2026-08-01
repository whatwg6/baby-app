import { useEffect, useRef, useState } from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';

import type {
  ActivityDetails,
  GrowthDetails,
  MilestoneDetails,
  NewRecordInput,
  RecordDetails,
  RecordDraft,
  RecordDraftAttachment,
  RecordType,
} from '../../domain/types';
import { parseRecordDraft } from '../../domain/validation';
import { colors, radius, spacing } from '../../ui/theme';
import { MediaServiceError } from '../media/mediaService';
import { ActivityFields, type EditableActivityDetails } from './forms/ActivityFields';
import { GrowthFields } from './forms/GrowthFields';
import { MilestoneFields } from './forms/MilestoneFields';
import { MomentFields } from './forms/MomentFields';

type EditableDetails =
  | null
  | GrowthDetails
  | EditableActivityDetails
  | MilestoneDetails;

type EditorValue = {
  occurredAt: string;
  note: string;
  attachments: RecordDraftAttachment[];
  details: EditableDetails;
};

type FormErrors = Partial<Record<'occurredAt' | 'details' | 'save', string>>;

export function RecordEditor({
  type,
  initialValue,
  now,
  onSubmit,
}: {
  type: RecordType;
  initialValue?: RecordDraft;
  now?: Date;
  onSubmit(input: RecordDraft): void | Promise<unknown>;
}) {
  const generatedNow = useRef<Date | null>(null);
  if (generatedNow.current === null) {
    generatedNow.current = new Date();
  }
  const referenceNow = now ?? generatedNow.current;
  const initialKey = JSON.stringify(initialValue ?? null);
  const previousInput = useRef({ initialKey, type, referenceNow });
  const savingRef = useRef(false);
  const [value, setValue] = useState(() => toEditorValue(type, initialValue, referenceNow));
  const [errors, setErrors] = useState<FormErrors>({});
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (
      previousInput.current.initialKey === initialKey &&
      previousInput.current.type === type &&
      previousInput.current.referenceNow === referenceNow
    ) {
      return;
    }
    previousInput.current = { initialKey, type, referenceNow };
    setValue(toEditorValue(type, initialValue, referenceNow));
    setErrors({});
  }, [initialKey, referenceNow, type]);

  const handleSave = async () => {
    if (savingRef.current) {
      return;
    }

    let input: RecordDraft;
    try {
      input = parseRecordDraft({
        type,
        occurredAt: value.occurredAt.trim(),
        note: value.note,
        details: value.details as RecordDetails,
        attachments: value.attachments,
      });
    } catch {
      setErrors(validationErrors(type, value));
      return;
    }

    savingRef.current = true;
    setSaving(true);
    setErrors({});
    try {
      await onSubmit(input);
    } catch (reason) {
      setErrors({
        save: reason instanceof MediaServiceError
          ? reason.message
          : '保存失败，已有数据未受影响',
      });
    } finally {
      savingRef.current = false;
      setSaving(false);
    }
  };

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      style={styles.keyboardAvoiding}
      testID="record-editor-keyboard-avoiding"
    >
      <ScrollView
        contentContainerStyle={styles.form}
        keyboardShouldPersistTaps="handled"
        testID="record-editor-scroll"
      >
        <View>
          <Text style={styles.label}>发生时间</Text>
          <TextInput
            accessibilityLabel="发生时间"
            autoCapitalize="none"
            onChangeText={(occurredAt) => setValue((current) => ({ ...current, occurredAt }))}
            placeholder="YYYY-MM-DDTHH:mm:ss.sssZ"
            style={styles.input}
            value={value.occurredAt}
          />
          {errors.occurredAt === undefined ? null : (
            <Text style={styles.error}>{errors.occurredAt}</Text>
          )}
        </View>

        <RecordSpecificFields
          attachments={value.attachments}
          initialValue={detailsFor(type, initialValue?.details)}
          onAdd={(attachment) => {
            setValue((current) => ({
              ...current,
              attachments: [...current.attachments, attachment],
            }));
          }}
          onChange={(details) => {
            setValue((current) => ({ ...current, details }));
          }}
          onRemove={(index) => {
            setValue((current) => ({
              ...current,
              attachments: current.attachments.filter((_, attachmentIndex) => attachmentIndex !== index),
            }));
          }}
          resetKey={`${type}:${initialKey}`}
          type={type}
        />
        {errors.details === undefined ? null : <Text style={styles.error}>{errors.details}</Text>}

        <View>
          <Text style={styles.label}>备注（可选）</Text>
          <TextInput
            accessibilityLabel="备注（可选）"
            multiline
            onChangeText={(note) => setValue((current) => ({ ...current, note }))}
            placeholder="记录一些细节"
            style={[styles.input, styles.noteInput]}
            value={value.note}
          />
        </View>

        {errors.save === undefined ? null : <Text style={styles.error}>{errors.save}</Text>}
        <Pressable
          accessibilityRole="button"
          disabled={saving}
          onPress={() => void handleSave()}
          style={[styles.saveButton, saving && styles.saveButtonDisabled]}
        >
          <Text style={styles.saveButtonText}>{saving ? '保存中…' : '保存'}</Text>
        </Pressable>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

export function toNewRecordInput(draft: RecordDraft): NewRecordInput {
  const { attachments, ...record } = draft;
  return {
    ...record,
    attachments: attachments.flatMap((attachment) => (
      attachment.kind === 'existing'
        ? [{
          id: attachment.id,
          mediaType: attachment.mediaType,
          filePath: attachment.filePath,
          thumbnailPath: attachment.thumbnailPath,
        }]
        : []
    )),
  };
}

function RecordSpecificFields({
  type,
  initialValue,
  attachments,
  resetKey,
  onChange,
  onAdd,
  onRemove,
}: {
  type: RecordType;
  initialValue: EditableDetails;
  attachments: RecordDraftAttachment[];
  resetKey: string;
  onChange(details: EditableDetails): void;
  onAdd(attachment: Extract<RecordDraftAttachment, { kind: 'picked' }>): void;
  onRemove(index: number): void;
}) {
  switch (type) {
    case 'moment':
      return <MomentFields attachments={attachments} onAdd={onAdd} onRemove={onRemove} />;
    case 'growth':
      return (
        <GrowthFields
          initialValue={asGrowthDetails(initialValue)}
          onChange={onChange}
          resetKey={resetKey}
        />
      );
    case 'activity':
      return (
        <ActivityFields
          initialValue={asActivityDetails(initialValue)}
          onChange={onChange}
          resetKey={resetKey}
        />
      );
    case 'milestone':
      return (
        <MilestoneFields
          attachments={attachments}
          initialValue={asMilestoneDetails(initialValue)}
          onChange={onChange}
          onAdd={onAdd}
          onRemove={onRemove}
          resetKey={resetKey}
        />
      );
  }
}

function toEditorValue(type: RecordType, initialValue: RecordDraft | undefined, now: Date): EditorValue {
  return {
    occurredAt: initialValue?.occurredAt ?? now.toISOString(),
    note: initialValue?.note ?? '',
    attachments: initialValue?.attachments ?? [],
    details: detailsFor(type, initialValue?.details),
  };
}

function detailsFor(type: RecordType, details: RecordDetails | undefined): EditableDetails {
  switch (type) {
    case 'moment':
      return null;
    case 'growth':
      return asGrowthDetails(details ?? null);
    case 'activity':
      return asActivityDetails(details ?? null);
    case 'milestone':
      return asMilestoneDetails(details ?? null);
  }
}

function asGrowthDetails(details: EditableDetails): GrowthDetails {
  if (details !== null && 'heightCm' in details && 'weightKg' in details && 'headCm' in details) {
    return details as GrowthDetails;
  }
  return { heightCm: null, weightKg: null, headCm: null };
}

function asActivityDetails(details: EditableDetails): EditableActivityDetails {
  if (details !== null && 'activityType' in details && 'amount' in details && 'durationMinutes' in details) {
    return details as EditableActivityDetails;
  }
  return { activityType: null, amount: null, durationMinutes: null };
}

function asMilestoneDetails(details: EditableDetails): MilestoneDetails {
  if (details !== null && 'title' in details && 'presetKey' in details) {
    return details as MilestoneDetails;
  }
  return { title: '', presetKey: null };
}

function validationErrors(type: RecordType, value: EditorValue): FormErrors {
  if (!isIsoTimestamp(value.occurredAt.trim())) {
    return { occurredAt: '请输入有效的发生时间' };
  }

  switch (type) {
    case 'moment':
      return { details: '请填写文字或添加媒体' };
    case 'growth': {
      const details = asGrowthDetails(value.details);
      if (details.heightCm === null && details.weightKg === null && details.headCm === null) {
        return { details: '请至少填写一项成长数据' };
      }
      return { details: '请输入有效的成长数据' };
    }
    case 'activity': {
      const details = asActivityDetails(value.details);
      if (details.activityType === null) {
        return { details: '请选择活动类型' };
      }
      return { details: '请输入有效的活动数据' };
    }
    case 'milestone':
      return { details: '请填写里程碑标题' };
  }
}

function isIsoTimestamp(value: string): boolean {
  return /(?:Z|[+-]\d{2}:\d{2})$/.test(value) && !Number.isNaN(Date.parse(value));
}

const styles = StyleSheet.create({
  keyboardAvoiding: { backgroundColor: colors.background, flex: 1 },
  form: { flexGrow: 1, gap: spacing.md, padding: spacing.lg },
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
  noteInput: { minHeight: 100, textAlignVertical: 'top' },
  error: { color: colors.danger, fontSize: 13, marginTop: spacing.xs },
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
