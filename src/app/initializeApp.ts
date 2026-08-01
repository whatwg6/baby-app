import { Directory, Paths } from 'expo-file-system';
import type { SQLiteDatabase } from 'expo-sqlite';

import { createDatabaseManager, type DatabaseManager } from '../data/database';
import {
  createSQLiteRepositories,
  type BabyRepository,
  type RecordRepository,
  type SQLiteRepositories,
} from '../data/repositories';
import {
  createBackupService,
  type BackupService,
} from '../features/backup/backupService';
import {
  mediaService,
  removeUnreferencedMedia,
  type MediaService,
} from '../features/media/mediaService';
import type { AppServices } from './AppProvider';

export interface AppMediaStorage {
  ensureDirectories(): Promise<void>;
  clearStaging(): Promise<void>;
}

type BackupFactory = (dependencies: {
  database: DatabaseManager;
  babies: BabyRepository;
  records: RecordRepository;
  media: MediaService;
}) => BackupService;

export type InitializeAppDependencies = {
  database?: DatabaseManager;
  media?: MediaService;
  mediaStorage?: AppMediaStorage;
  repositoryFactory?(database: SQLiteDatabase): SQLiteRepositories;
  backupFactory?: BackupFactory;
  cleanupMedia?: typeof removeUnreferencedMedia;
};

export async function initializeApp(
  dependencies: InitializeAppDependencies = {},
): Promise<AppServices> {
  const database = dependencies.database ?? createDatabaseManager();
  const media = dependencies.media ?? mediaService;
  const mediaStorage = dependencies.mediaStorage ?? createAppMediaStorage();
  const repositoryFactory = dependencies.repositoryFactory ?? createSQLiteRepositories;
  const cleanupMedia = dependencies.cleanupMedia ?? removeUnreferencedMedia;

  await mediaStorage.ensureDirectories();
  const databaseHandle = await database.initialize();
  const repositories = repositoryFactory(databaseHandle);
  await mediaStorage.clearStaging();
  await cleanupMedia({
    babies: repositories.babies,
    records: repositories.records,
    media,
  });

  return assembleAppServices({
    database,
    media,
    repositories,
    backupFactory: dependencies.backupFactory,
  });
}

export function assembleAppServices({
  database,
  media,
  repositories,
  backupFactory = createBackupService,
}: {
  database: DatabaseManager;
  media: MediaService;
  repositories: SQLiteRepositories;
  backupFactory?: BackupFactory;
}): AppServices {
  const backup = backupFactory({
    database,
    babies: repositories.babies,
    records: repositories.records,
    media,
  });
  return {
    babies: repositories.babies,
    records: repositories.records,
    media,
    backup,
    database,
  };
}

export function createAppMediaStorage(
  documentDirectory = Paths.document.uri,
): AppMediaStorage {
  const stagingDirectory = appendPath(documentDirectory, 'staging');
  const mediaDirectory = appendPath(documentDirectory, 'media');

  return {
    async ensureDirectories() {
      new Directory(stagingDirectory).create({ idempotent: true, intermediates: true });
      new Directory(mediaDirectory).create({ idempotent: true, intermediates: true });
    },
    async clearStaging() {
      const staging = new Directory(stagingDirectory);
      if (!staging.exists) {
        return;
      }
      for (const entry of staging.list()) {
        entry.delete();
      }
    },
  };
}

function appendPath(directory: string, name: string): string {
  return `${directory.replace(/\/+$/, '')}/${name}`;
}
