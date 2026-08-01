export interface BackupManifestV1 {
  format: 'baby-growth-backup';
  version: 1;
  createdAt: string;
  database: { path: 'database/app.db'; sha256: string };
  media: Array<{ path: string; sha256: string; size: number }>;
}

const SHA256_PATTERN = /^[a-f0-9]{64}$/i;

export function parseBackupManifest(value: unknown): BackupManifestV1 {
  if (!isObject(value) || value.format !== 'baby-growth-backup') {
    throw new Error('This is not a baby growth backup.');
  }
  if (value.version !== 1) {
    throw new Error(`Backup version ${String(value.version)} is not supported.`);
  }
  if (typeof value.createdAt !== 'string' || !Number.isFinite(Date.parse(value.createdAt))) {
    throw new Error('Backup creation time is invalid.');
  }
  if (!isObject(value.database) || value.database.path !== 'database/app.db' ||
      !isSha256(value.database.sha256)) {
    throw new Error('Backup database manifest is invalid.');
  }
  if (!Array.isArray(value.media)) {
    throw new Error('Backup media manifest is invalid.');
  }

  const media = value.media.map((entry) => {
    if (!isObject(entry) || typeof entry.path !== 'string' ||
        !isSha256(entry.sha256) || !Number.isSafeInteger(entry.size) ||
        (entry.size as number) < 0) {
      throw new Error('Backup media manifest is invalid.');
    }
    return {
      path: entry.path,
      sha256: entry.sha256.toLowerCase(),
      size: entry.size as number,
    };
  });
  const normalizedPaths = media.map((entry) => (
    entry.path.normalize('NFC').toLocaleLowerCase('en-US')
  ));
  if (new Set(normalizedPaths).size !== normalizedPaths.length) {
    throw new Error('Backup media manifest contains duplicate paths.');
  }

  return {
    format: 'baby-growth-backup',
    version: 1,
    createdAt: value.createdAt,
    database: {
      path: 'database/app.db',
      sha256: value.database.sha256.toLowerCase(),
    },
    media,
  };
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isSha256(value: unknown): value is string {
  return typeof value === 'string' && SHA256_PATTERN.test(value);
}
