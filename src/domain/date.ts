import type { TimelineRecord } from './types';

export interface RecordDayGroup {
  key: string;
  records: TimelineRecord[];
}

function parseLocalDate(value: string): Date {
  const [year, month, day] = value.split('-').map(Number);
  const parsed = new Date(year, month - 1, day);

  if (
    parsed.getFullYear() !== year ||
    parsed.getMonth() !== month - 1 ||
    parsed.getDate() !== day
  ) {
    throw new Error('Invalid birth date.');
  }

  return parsed;
}

function formatLocalDay(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');

  return `${year}-${month}-${day}`;
}

export function calculateAgeLabel(birthDate: string, now = new Date()): string {
  const birth = parseLocalDate(birthDate);
  let years = now.getFullYear() - birth.getFullYear();
  let months = now.getMonth() - birth.getMonth();
  let days = now.getDate() - birth.getDate();

  if (days < 0) {
    months -= 1;
    days += new Date(now.getFullYear(), now.getMonth(), 0).getDate();
  }
  if (months < 0) {
    years -= 1;
    months += 12;
  }

  if (years > 0) {
    return months > 0 ? `${years}岁${months}个月` : `${years}岁`;
  }
  if (months > 0) {
    return `${months}个月`;
  }

  return `${Math.max(days, 0)}天`;
}

export function groupRecordsByDay(records: TimelineRecord[]): RecordDayGroup[] {
  const groups = new Map<string, TimelineRecord[]>();
  const orderedRecords = [...records].sort(
    (left, right) =>
      new Date(right.occurredAt).getTime() - new Date(left.occurredAt).getTime(),
  );

  for (const record of orderedRecords) {
    const key = formatLocalDay(new Date(record.occurredAt));
    const group = groups.get(key);
    if (group === undefined) {
      groups.set(key, [record]);
    } else {
      group.push(record);
    }
  }

  return Array.from(groups, ([key, groupedRecords]) => ({
    key,
    records: groupedRecords,
  }));
}
