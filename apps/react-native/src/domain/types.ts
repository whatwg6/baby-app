export type RecordType = 'moment' | 'growth' | 'activity' | 'milestone';
export type ActivityType = 'feeding' | 'sleep' | 'diaper';
export type MediaType = 'image' | 'video';

export interface Baby {
  id: string;
  name: string;
  birthDate: string;
  sex: 'female' | 'male' | null;
  avatarPath: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface BabyInput {
  name: string;
  birthDate: string;
  sex: 'female' | 'male' | null;
  avatarPath: string | null;
}

export interface Attachment {
  id: string;
  recordId: string;
  mediaType: MediaType;
  filePath: string;
  thumbnailPath: string | null;
  createdAt: string;
}

/** Measurements only prevent obvious entry mistakes; they are not medical advice. */
export interface GrowthDetails {
  heightCm: number | null;
  weightKg: number | null;
  headCm: number | null;
}

export interface ActivityDetails {
  activityType: ActivityType;
  amount: number | null;
  durationMinutes: number | null;
}

export interface MilestoneDetails {
  title: string;
  presetKey: string | null;
}

export type MomentDetails = null;
export type RecordDetails =
  | MomentDetails
  | GrowthDetails
  | ActivityDetails
  | MilestoneDetails;

export interface TimelineRecord {
  id: string;
  type: RecordType;
  occurredAt: string;
  note: string | null;
  details: RecordDetails;
  attachments: Attachment[];
  createdAt: string;
  updatedAt: string;
}

export type RecordDraftAttachment =
  | { kind: 'picked'; sourceUri: string; mediaType: MediaType }
  | {
      kind: 'existing';
      id: string;
      mediaType: MediaType;
      filePath: string;
      thumbnailPath: string | null;
    };

export interface NewAttachmentInput {
  id?: string;
  mediaType: MediaType;
  filePath: string;
  thumbnailPath: string | null;
}

export interface RecordDraft {
  type: RecordType;
  occurredAt: string;
  note: string | null;
  details: RecordDetails;
  attachments: RecordDraftAttachment[];
}

export interface NewRecordInput extends Omit<RecordDraft, 'attachments'> {
  attachments: NewAttachmentInput[];
}
