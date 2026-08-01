import type { TimelineRecord } from '../types';
import { calculateAgeLabel, groupRecordsByDay } from '../date';

const records: TimelineRecord[] = [
  {
    id: 'older',
    type: 'moment',
    occurredAt: '2026-07-31T21:00:00',
    note: '昨天',
    details: null,
    attachments: [],
    createdAt: '2026-07-31T21:00:00',
    updatedAt: '2026-07-31T21:00:00',
  },
  {
    id: 'newest',
    type: 'milestone',
    occurredAt: '2026-08-01T18:00:00',
    note: null,
    details: { title: '会翻身', presetKey: null },
    attachments: [],
    createdAt: '2026-08-01T18:00:00',
    updatedAt: '2026-08-01T18:00:00',
  },
  {
    id: 'same-day-earlier',
    type: 'growth',
    occurredAt: '2026-08-01T08:00:00',
    note: null,
    details: { heightCm: 65, weightKg: null, headCm: null },
    attachments: [],
    createdAt: '2026-08-01T08:00:00',
    updatedAt: '2026-08-01T08:00:00',
  },
];

describe('calculateAgeLabel', () => {
  test('calculates natural year and month differences across a year boundary', () => {
    expect(calculateAgeLabel('2025-06-15', new Date('2026-08-01'))).toBe(
      '1岁1个月',
    );
  });

  test('uses days before the first full month', () => {
    expect(calculateAgeLabel('2026-07-25', new Date('2026-08-01'))).toBe('7天');
  });
});

describe('groupRecordsByDay', () => {
  test('orders records descending and groups them by the device-local day', () => {
    const groups = groupRecordsByDay(records);

    expect(groups.map((group) => group.key)).toEqual(['2026-08-01', '2026-07-31']);
    expect(groups[0].records.map((record) => record.id)).toEqual([
      'newest',
      'same-day-earlier',
    ]);
  });
});
