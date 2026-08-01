import { z } from 'zod';

import type { BabyInput, RecordDraft } from './types';

const mediaTypeSchema = z.enum(['image', 'video']);
const nullableNoteSchema = z.preprocess(
  (value) => (typeof value === 'string' && value.trim() === '' ? null : value),
  z.string().trim().min(1).nullable(),
);
const nullableFiniteNumberSchema = z.number().finite().nullable().optional().default(null);

const attachmentSchema = z.discriminatedUnion('kind', [
  z.object({
    kind: z.literal('picked'),
    sourceUri: z.string().min(1),
    mediaType: mediaTypeSchema,
  }),
  z.object({
    kind: z.literal('existing'),
    id: z.string().min(1),
    mediaType: mediaTypeSchema,
    filePath: z.string().min(1),
    thumbnailPath: z.string().min(1).nullable(),
  }),
]);

const baseRecordSchema = {
  occurredAt: z.string().datetime({ offset: true }),
  note: nullableNoteSchema,
  attachments: z.array(attachmentSchema),
};

const recordDraftSchema = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('moment'),
    ...baseRecordSchema,
    details: z.null(),
  }).superRefine((record, context) => {
    if (record.note === null && record.attachments.length === 0) {
      context.addIssue({ code: 'custom', message: 'A moment needs text or media.' });
    }
  }),
  z.object({
    type: z.literal('growth'),
    ...baseRecordSchema,
    details: z.object({
      heightCm: nullableFiniteNumberSchema.pipe(z.number().min(20).max(250).nullable()),
      weightKg: nullableFiniteNumberSchema.pipe(z.number().min(0.2).max(300).nullable()),
      headCm: nullableFiniteNumberSchema.pipe(z.number().min(10).max(100).nullable()),
    }),
  }).superRefine((record, context) => {
    if (
      record.details.heightCm === null &&
      record.details.weightKg === null &&
      record.details.headCm === null
    ) {
      context.addIssue({ code: 'custom', message: 'A growth record needs a measurement.' });
    }
  }),
  z.object({
    type: z.literal('activity'),
    ...baseRecordSchema,
    details: z.object({
      activityType: z.enum(['feeding', 'sleep', 'diaper']),
      amount: nullableFiniteNumberSchema.pipe(z.number().min(0).nullable()),
      durationMinutes: nullableFiniteNumberSchema.pipe(z.number().positive().nullable()),
    }),
  }),
  z.object({
    type: z.literal('milestone'),
    ...baseRecordSchema,
    details: z.object({
      title: z.string().trim().min(1),
      presetKey: z.string().trim().min(1).nullable().optional().default(null),
    }),
  }),
]);

const babyInputSchema = z.object({
  name: z.string().trim().min(1),
  birthDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  sex: z.enum(['female', 'male']).nullable().optional().default(null),
  avatarPath: z.string().min(1).nullable().optional().default(null),
});

function parseLocalDate(value: string): Date | null {
  const [year, month, day] = value.split('-').map(Number);
  const parsed = new Date(year, month - 1, day);

  return parsed.getFullYear() === year &&
    parsed.getMonth() === month - 1 &&
    parsed.getDate() === day
    ? parsed
    : null;
}

export function parseBabyInput(input: unknown, now = new Date()): BabyInput {
  const baby = babyInputSchema.parse(input);
  const birthDate = parseLocalDate(baby.birthDate);
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

  if (birthDate === null || birthDate > today) {
    throw new Error('Birth date cannot be in the future.');
  }

  return baby;
}

export function parseRecordDraft(input: unknown): RecordDraft {
  return recordDraftSchema.parse(input) as RecordDraft;
}
