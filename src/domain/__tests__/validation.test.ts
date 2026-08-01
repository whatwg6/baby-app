import { parseBabyInput, parseRecordDraft } from '../validation';

const now = new Date('2026-08-01T12:00:00.000Z');
const occurredAt = '2026-08-01T09:30:00.000Z';

describe('parseBabyInput', () => {
  test('rejects a birth date after the injected current day', () => {
    expect(() =>
      parseBabyInput({ name: '安安', birthDate: '2099-01-01' }, now),
    ).toThrow();
  });
});

describe('parseRecordDraft', () => {
  test('rejects a growth record with no measurements', () => {
    expect(() =>
      parseRecordDraft({
        type: 'growth',
        occurredAt,
        note: null,
        details: {},
        attachments: [],
      }),
    ).toThrow();
  });

  test('rejects a moment without text or media', () => {
    expect(() =>
      parseRecordDraft({
        type: 'moment',
        occurredAt,
        note: '   ',
        details: null,
        attachments: [],
      }),
    ).toThrow();
  });

  test('accepts a milestone with a title', () => {
    expect(
      parseRecordDraft({
        type: 'milestone',
        occurredAt,
        note: null,
        details: { title: '第一次翻身', presetKey: 'roll-over' },
        attachments: [],
      }),
    ).toEqual({
      type: 'milestone',
      occurredAt,
      note: null,
      details: { title: '第一次翻身', presetKey: 'roll-over' },
      attachments: [],
    });
  });

  test('rejects a moment carrying details for another record type', () => {
    expect(() =>
      parseRecordDraft({
        type: 'moment',
        occurredAt,
        note: '宝宝笑了',
        details: { title: '不应存在', presetKey: null },
        attachments: [],
      }),
    ).toThrow();
  });

  test('rejects out-of-range growth measurements without medical interpretation', () => {
    expect(() =>
      parseRecordDraft({
        type: 'growth',
        occurredAt,
        note: null,
        details: { heightCm: 251, weightKg: null, headCm: null },
        attachments: [],
      }),
    ).toThrow();
  });

  test('accepts an activity type when amount, duration, and note are all omitted', () => {
    expect(parseRecordDraft({
      type: 'activity',
      occurredAt,
      note: null,
      details: { activityType: 'feeding', amount: null, durationMinutes: null },
      attachments: [],
    })).toEqual({
      type: 'activity',
      occurredAt,
      note: null,
      details: { activityType: 'feeding', amount: null, durationMinutes: null },
      attachments: [],
    });
  });
});
