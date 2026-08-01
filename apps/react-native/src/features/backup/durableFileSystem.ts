import { requireOptionalNativeModule } from 'expo';

type DurableFileSystemModule = {
  syncFile(path: string): Promise<void>;
  syncDirectory(path: string): Promise<void>;
};

const nativeModule = requireOptionalNativeModule<DurableFileSystemModule>(
  'ExpoDurableFileSystem',
);

export function syncFileToStableStorage(path: string): Promise<void> {
  return getNativeModule().syncFile(path);
}

export function syncDirectoryToStableStorage(path: string): Promise<void> {
  return getNativeModule().syncDirectory(path);
}

function getNativeModule(): DurableFileSystemModule {
  if (nativeModule === null) {
    throw new Error(
      'Durable restore requires an iOS or Android build containing ExpoDurableFileSystem.',
    );
  }
  return nativeModule;
}
