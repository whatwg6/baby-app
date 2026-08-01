import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../data/database/app_database.dart';
import '../../media/domain/media_service.dart';
import '../domain/backup_service.dart';

typedef BackupFilePicker = Future<String?> Function();

class ClearAllDataCleanupException implements Exception {
  ClearAllDataCleanupException({
    required Set<String> paths,
    required this.mediaRemovalError,
    required this.queueError,
  }) : paths = Set<String>.unmodifiable(paths);

  final Set<String> paths;
  final Object mediaRemovalError;
  final Object queueError;

  @override
  String toString() => '数据已清空，但媒体清理排队失败';
}

Future<void> clearAllData({
  required AppDatabase database,
  required MediaService mediaService,
  required Future<void> Function(Set<String> paths) queueOrphanCleanup,
}) async {
  final paths = await database.transaction((transaction) async {
    final referenced = <String>{};
    final babies = await transaction.query('baby', columns: ['avatar_path']);
    for (final row in babies) {
      final avatar = row['avatar_path'] as String?;
      if (avatar != null && avatar.isNotEmpty) referenced.add(avatar);
    }
    final attachments = await transaction.query(
      'attachments',
      columns: ['file_path', 'thumbnail_path'],
    );
    for (final row in attachments) {
      referenced.add(row['file_path']! as String);
      final thumbnail = row['thumbnail_path'] as String?;
      if (thumbnail != null && thumbnail.isNotEmpty) {
        referenced.add(thumbnail);
      }
    }
    await transaction.delete('records');
    await transaction.delete('baby');
    return referenced;
  });

  if (paths.isEmpty) return;
  try {
    await mediaService.remove(paths);
  } catch (mediaRemovalError) {
    try {
      await queueOrphanCleanup(paths);
    } catch (queueError) {
      throw ClearAllDataCleanupException(
        paths: paths,
        mediaRemovalError: mediaRemovalError,
        queueError: queueError,
      );
    }
  }
}

class BackupActions extends StatefulWidget {
  const BackupActions({
    super.key,
    required this.service,
    this.pickBackup,
    this.onRestored,
  });

  final BackupService service;
  final BackupFilePicker? pickBackup;
  final Future<void> Function()? onRestored;

  @override
  State<BackupActions> createState() => _BackupActionsState();
}

class _BackupActionsState extends State<BackupActions> {
  var _busy = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton.icon(
        onPressed: _busy ? null : _export,
        icon: const Icon(Icons.ios_share_outlined),
        label: const Text('导出备份'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy ? null : _restore,
        icon: const Icon(Icons.restore_outlined),
        label: const Text('恢复备份'),
      ),
    ],
  );

  Future<void> _export() => _run(() async {
    await widget.service.exportBackup();
  });

  Future<void> _restore() => _run(() async {
    final archivePath = await (widget.pickBackup ?? _pickBackup)();
    if (archivePath == null) return;
    final inspected = await widget.service.inspect(archivePath);
    await widget.service.restore(inspected);
    await widget.onRestored?.call();
  });

  Future<void> _run(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static Future<String?> _pickBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    return result?.files.single.path;
  }
}
