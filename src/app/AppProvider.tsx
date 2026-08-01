import { createContext, useContext, type ReactNode } from 'react';

import type { DatabaseManager } from '../data/database';
import type { BabyRepository, RecordRepository } from '../data/repositories';
import { BabyRepositoryProvider } from '../features/baby/useBaby';
import { BackupServiceProvider } from '../features/backup/BackupActions';
import type { BackupService } from '../features/backup/backupService';
import type { MediaService } from '../features/media/mediaService';
import { RecordRepositoryProvider } from '../features/records/RecordRepositoryProvider';

export interface AppServices {
  babies: BabyRepository;
  records: RecordRepository;
  media: MediaService;
  backup: BackupService;
  database: DatabaseManager;
}

const AppServicesContext = createContext<AppServices | null>(null);

export function AppProvider({
  services,
  children,
}: {
  services: AppServices;
  children: ReactNode;
}) {
  return (
    <AppServicesContext.Provider value={services}>
      <BackupServiceProvider service={services.backup}>
        <BabyRepositoryProvider repository={services.babies} media={services.media}>
          <RecordRepositoryProvider repository={services.records}>
            {children}
          </RecordRepositoryProvider>
        </BabyRepositoryProvider>
      </BackupServiceProvider>
    </AppServicesContext.Provider>
  );
}

export function useAppServices(): AppServices {
  const services = useContext(AppServicesContext);
  if (services === null) {
    throw new Error('useAppServices must be used within AppProvider.');
  }
  return services;
}
