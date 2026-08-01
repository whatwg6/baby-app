import type { RecordRepository } from '../../data/repositories';
import type {
  NewAttachmentInput,
  NewRecordInput,
  RecordDraft,
  TimelineRecord,
} from '../../domain/types';
import type { MediaService, StagedMedia } from './mediaStorage';

export interface MediaCleanupIssue {
  scope: 'record' | 'avatar';
  paths: string[];
  cause: unknown;
}

export const CLEANUP_PENDING_MESSAGE = '已保存，旧媒体将在稍后清理';

type RecordMediaDependencies = {
  records: RecordRepository;
  media: MediaService;
  onCleanupPending?(issue: MediaCleanupIssue): void;
};

export async function saveRecordWithMedia(
  input: RecordDraft,
  dependencies: RecordMediaDependencies,
): Promise<TimelineRecord> {
  return persistRecordWithMedia('create', null, input, dependencies);
}

export async function updateRecordWithMedia(
  id: string,
  input: RecordDraft,
  dependencies: RecordMediaDependencies,
): Promise<TimelineRecord> {
  const previous = await dependencies.records.get(id);
  if (previous === null) {
    throw new Error(`Record ${id} was not found.`);
  }

  const saved = await persistRecordWithMedia('update', id, input, dependencies);
  const retainedPaths = new Set(attachmentPaths(saved));
  const removedPaths = attachmentPaths(previous).filter((path) => !retainedPaths.has(path));
  if (removedPaths.length > 0) {
    try {
      await dependencies.media.remove(removedPaths);
    } catch (cause) {
      dependencies.onCleanupPending?.({ scope: 'record', paths: removedPaths, cause });
    }
  }
  return saved;
}

async function persistRecordWithMedia(
  operation: 'create' | 'update',
  id: string | null,
  draft: RecordDraft,
  dependencies: RecordMediaDependencies,
): Promise<TimelineRecord> {
  const stagedMedia: StagedMedia[] = [];
  const committedPaths: string[] = [];

  try {
    for (const attachment of draft.attachments) {
      if (attachment.kind === 'picked') {
        stagedMedia.push(await dependencies.media.stage({
          uri: attachment.sourceUri,
          mediaType: attachment.mediaType,
        }));
      }
    }
  } catch (error) {
    return cleanupAndRethrow(
      error,
      stagedMedia.map((staged) => () => dependencies.media.rollback(staged)),
      '媒体暂存与回滚均失败',
    );
  }

  const repositoryInput = toRepositoryInput(draft, stagedMedia);
  try {
    return await dependencies.records.withTransaction(async (transaction) => {
      const saved = operation === 'create'
        ? await transaction.create(repositoryInput)
        : await transaction.update(requireId(id), repositoryInput);

      for (const staged of stagedMedia) {
        const committed = await dependencies.media.commit(staged);
        committedPaths.push(committed.filePath);
        if (committed.thumbnailPath !== null) {
          committedPaths.push(committed.thumbnailPath);
        }
      }
      return saved;
    });
  } catch (error) {
    const cleanup = stagedMedia.map((staged) => () => dependencies.media.rollback(staged));
    if (committedPaths.length > 0) {
      cleanup.push(() => dependencies.media.remove(committedPaths));
    }
    return cleanupAndRethrow(error, cleanup, '记录保存与媒体清理均失败');
  }
}

function toRepositoryInput(draft: RecordDraft, stagedMedia: StagedMedia[]): NewRecordInput {
  let pickedIndex = 0;
  const attachments: NewAttachmentInput[] = draft.attachments.map((attachment) => {
    if (attachment.kind === 'existing') {
      return {
        id: attachment.id,
        mediaType: attachment.mediaType,
        filePath: attachment.filePath,
        thumbnailPath: attachment.thumbnailPath,
      };
    }

    const staged = stagedMedia[pickedIndex];
    pickedIndex += 1;
    if (staged === undefined) {
      throw new Error('Picked media was not staged.');
    }
    return {
      mediaType: attachment.mediaType,
      filePath: staged.finalPath,
      thumbnailPath: staged.thumbnailFinalPath,
    };
  });

  return {
    type: draft.type,
    occurredAt: draft.occurredAt,
    note: draft.note,
    details: draft.details,
    attachments,
  };
}

function attachmentPaths(record: TimelineRecord): string[] {
  return record.attachments.flatMap((attachment) => [
    attachment.filePath,
    ...(attachment.thumbnailPath === null ? [] : [attachment.thumbnailPath]),
  ]);
}

function requireId(id: string | null): string {
  if (id === null) {
    throw new Error('An update requires a record id.');
  }
  return id;
}

async function cleanupAndRethrow(
  primaryError: unknown,
  tasks: Array<() => Promise<void>>,
  message: string,
): Promise<never> {
  const results = await Promise.allSettled(tasks.map((task) => task()));
  const cleanupErrors = results.flatMap((result) => (
    result.status === 'rejected' ? [result.reason] : []
  ));
  if (cleanupErrors.length > 0) {
    throw new AggregateError([primaryError, ...cleanupErrors], message);
  }
  throw primaryError;
}
