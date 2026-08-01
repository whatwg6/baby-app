import 'backup_manifest.dart';

abstract interface class BackupService {
  Future<String> exportBackup();

  Future<BackupInspection> inspect(String archivePath);

  Future<void> restore(BackupInspection inspected);

  Future<void> removeExpiredExports(Duration maxAge);
}

class BackupInspection {
  const BackupInspection({
    required this.temporaryDirectory,
    required this.manifest,
  });

  final String temporaryDirectory;
  final BackupManifestV1 manifest;
}

class BackupException implements Exception {
  const BackupException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message: $cause';
}

class BackupShareException extends BackupException {
  const BackupShareException(this.archivePath, Object cause)
    : super('分享失败，备份已保留在 $archivePath', cause);

  final String archivePath;
}

class BackupRollbackException extends BackupException {
  const BackupRollbackException({
    required this.recoveryPath,
    required this.originalError,
    required this.rollbackError,
  }) : super('恢复失败，旧数据保留在 $recoveryPath', rollbackError);

  final String recoveryPath;
  final Object originalError;
  final Object rollbackError;
}
