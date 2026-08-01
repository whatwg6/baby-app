import type { BabyInput, NewRecordInput } from '../domain/types';

export const babyInputFixture = (): BabyInput => ({
  name: '安安',
  birthDate: '2026-01-15',
  sex: 'female',
  avatarPath: 'file:///avatars/anan.jpg',
});

export const momentInputFixture = (
  overrides: Partial<NewRecordInput> = {},
): NewRecordInput => ({
  type: 'moment',
  occurredAt: '2026-08-01T09:30:00.000Z',
  note: '第一次看向镜头',
  details: null,
  attachments: [
    {
      id: 'attachment-image-1',
      mediaType: 'image',
      filePath: 'file:///media/first-look.jpg',
      thumbnailPath: 'file:///media/first-look-thumb.jpg',
    },
  ],
  ...overrides,
});

export const recordVariantFixtures = (): NewRecordInput[] => [
  momentInputFixture(),
  {
    type: 'growth',
    occurredAt: '2026-08-02T09:30:00.000Z',
    note: null,
    details: { heightCm: 66.2, weightKg: 7.4, headCm: null },
    attachments: [],
  },
  {
    type: 'activity',
    occurredAt: '2026-08-03T09:30:00.000Z',
    note: '午后小睡',
    details: { activityType: 'sleep', amount: null, durationMinutes: 45 },
    attachments: [],
  },
  {
    type: 'milestone',
    occurredAt: '2026-08-04T09:30:00.000Z',
    note: null,
    details: { title: '会翻身', presetKey: 'roll-over' },
    attachments: [],
  },
];
