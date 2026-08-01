import 'package:flutter/material.dart';

import '../../../data/repositories/record_repository.dart';
import '../../media/domain/media_service.dart';

typedef OrphanCleanupQueue = Future<void> Function(Set<String> paths);

class DeleteRecordButton extends StatefulWidget {
  const DeleteRecordButton({
    super.key,
    required this.recordId,
    required this.repository,
    required this.mediaService,
    required this.queueOrphanCleanup,
    this.onDeleted,
  });

  final String recordId;
  final RecordRepository repository;
  final MediaService mediaService;
  final OrphanCleanupQueue queueOrphanCleanup;
  final Future<void> Function()? onDeleted;

  @override
  State<DeleteRecordButton> createState() => _DeleteRecordButtonState();
}

class _DeleteRecordButtonState extends State<DeleteRecordButton> {
  var _deleting = false;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: _deleting ? null : _confirm,
    icon: const Icon(Icons.delete_outline),
    label: const Text('删除'),
  );

  Future<void> _confirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text('删除这条记录？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);

    late final Set<String> paths;
    try {
      final attachments = await widget.repository.delete(widget.recordId);
      paths = <String>{
        for (final attachment in attachments) attachment.filePath,
        for (final attachment in attachments)
          if (attachment.thumbnailPath != null) attachment.thumbnailPath!,
      };
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
      }
      if (mounted) setState(() => _deleting = false);
      return;
    }

    var cleanupQueued = false;
    var queueFailed = false;
    if (paths.isNotEmpty) {
      try {
        await widget.mediaService.remove(paths);
      } catch (_) {
        try {
          await widget.queueOrphanCleanup(paths);
          cleanupQueued = true;
        } catch (_) {
          queueFailed = true;
        }
      }
    }
    try {
      await widget.onDeleted?.call();
    } catch (_) {
      // The database deletion is terminal; a refresh/navigation failure must
      // never invite a second destructive attempt.
    }
    if (mounted) {
      setState(() => _deleting = false);
      if (queueFailed || cleanupQueued) {
        final message = queueFailed ? '记录已删除，但媒体清理排队失败' : '记录已删除，媒体将在稍后清理';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }
}
