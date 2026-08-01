import { Directory, File, Paths } from 'expo-file-system';

import type { RecoverySentinelStore } from './database';

const RECOVERY_SENTINEL_FILE = 'baby-growth-recovery-required.json';

export function createExpoRecoverySentinelStore(
  documentDirectory = Paths.document.uri,
): RecoverySentinelStore {
  const documents = new Directory(documentDirectory);
  const sentinel = new File(appendPath(documentDirectory, RECOVERY_SENTINEL_FILE));
  return {
    isRecoveryRequired: () => documents
      .list()
      .some((entry) => entry.name === RECOVERY_SENTINEL_FILE),
    markRecoveryRequired: () => {
      // Create the marker before writing metadata so an interrupted/partial
      // write still leaves the sentinel name visible to the directory scan.
      sentinel.create({ overwrite: true });
      sentinel.write(JSON.stringify({
        format: 'baby-growth-recovery-required',
        version: 1,
        createdAt: new Date().toISOString(),
      }));
    },
  };
}

function appendPath(directory: string, name: string): string {
  return `${directory.replace(/\/+$/, '')}/${name}`;
}
