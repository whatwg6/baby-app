import type { SQLiteDatabase } from 'expo-sqlite';

import { rebaseLegacyPrivateMediaPath } from '../features/media/mediaPaths';

type BabyMediaPathRow = {
  id: string;
  path: string;
};

type AttachmentMediaPathRow = {
  id: string;
  filePath: string;
  thumbnailPath: string | null;
};

export async function repairMediaPaths(
  database: SQLiteDatabase,
  currentMediaRoot: string,
): Promise<void> {
  await database.withExclusiveTransactionAsync(async (transaction) => {
    const babies = await transaction.getAllAsync<BabyMediaPathRow>(`
      SELECT id, avatar_path AS path
      FROM baby
      WHERE avatar_path IS NOT NULL;
    `);
    const attachments = await transaction.getAllAsync<AttachmentMediaPathRow>(`
      SELECT
        id,
        file_path AS filePath,
        thumbnail_path AS thumbnailPath
      FROM attachments;
    `);

    for (const baby of babies) {
      const repaired = rebaseLegacyPrivateMediaPath(baby.path, currentMediaRoot);
      if (repaired !== baby.path) {
        await transaction.runAsync(
          'UPDATE baby SET avatar_path = ? WHERE id = ?;',
          [repaired, baby.id],
        );
      }
    }

    for (const attachment of attachments) {
      const repairedFile = rebaseLegacyPrivateMediaPath(
        attachment.filePath,
        currentMediaRoot,
      );
      const repairedThumbnail = attachment.thumbnailPath === null
        ? null
        : rebaseLegacyPrivateMediaPath(attachment.thumbnailPath, currentMediaRoot);
      if (repairedFile !== attachment.filePath ||
          repairedThumbnail !== attachment.thumbnailPath) {
        await transaction.runAsync(
          `UPDATE attachments
           SET file_path = ?, thumbnail_path = ?
           WHERE id = ?;`,
          [repairedFile, repairedThumbnail, attachment.id],
        );
      }
    }
  });
}
