import { File, Paths } from 'expo-file-system';

import type { RecoverySentinelStore } from './database';

const RECOVERY_SENTINEL_FILE = 'baby-growth-recovery-required.json';

export function createExpoRecoverySentinelStore(
  documentDirectory = Paths.document.uri,
): RecoverySentinelStore {
  const sentinel = new File(appendPath(documentDirectory, RECOVERY_SENTINEL_FILE));
  return {
    isRecoveryRequired: () => sentinel.exists,
    markRecoveryRequired: () => {
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
