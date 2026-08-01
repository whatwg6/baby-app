import type { MediaService } from '../features/media/mediaService';

export type MaintenanceOperation = 'clear' | 'restore';

export type MaintenanceSnapshot = {
  active: boolean;
  operation: MaintenanceOperation | null;
  warning: string | null;
};

export type MaintenanceLease = {
  finish(result?: { warning?: string }): void;
};

export interface MaintenanceCoordinator {
  getSnapshot(): MaintenanceSnapshot;
  subscribe(listener: () => void): () => void;
  begin(operation: MaintenanceOperation): MaintenanceLease;
  assertWritable(): void;
  publishWarning(warning: string): void;
  clearWarning(): void;
}

export class MaintenanceInProgressError extends Error {
  constructor() {
    super('本地数据维护中，请稍后重试');
    this.name = 'MaintenanceInProgressError';
  }
}

export function createMaintenanceCoordinator(): MaintenanceCoordinator {
  let snapshot: MaintenanceSnapshot = { active: false, operation: null, warning: null };
  let leaseId = 0;
  const listeners = new Set<() => void>();
  const publish = (next: MaintenanceSnapshot) => {
    snapshot = next;
    for (const listener of listeners) {
      listener();
    }
  };

  return {
    getSnapshot: () => snapshot,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    begin(operation) {
      if (snapshot.active) {
        throw new MaintenanceInProgressError();
      }
      leaseId += 1;
      const currentLease = leaseId;
      let finished = false;
      publish({ active: true, operation, warning: snapshot.warning });
      return {
        finish(result) {
          if (finished || currentLease !== leaseId) {
            return;
          }
          finished = true;
          publish({
            active: false,
            operation: null,
            warning: result?.warning ?? snapshot.warning,
          });
        },
      };
    },
    assertWritable() {
      if (snapshot.active) {
        throw new MaintenanceInProgressError();
      }
    },
    publishWarning(warning) {
      publish({ ...snapshot, warning });
    },
    clearWarning() {
      if (snapshot.warning !== null) {
        publish({ ...snapshot, warning: null });
      }
    },
  };
}

export function createMaintenanceAwareMediaService(
  media: MediaService,
  maintenance: MaintenanceCoordinator,
): MediaService {
  return {
    async stage(input) {
      maintenance.assertWritable();
      return media.stage(input);
    },
    async commit(staged) {
      maintenance.assertWritable();
      return media.commit(staged);
    },
    rollback: (staged) => media.rollback(staged),
    remove: (paths) => media.remove(paths),
    removeOrphans: (paths) => media.removeOrphans(paths),
  };
}
