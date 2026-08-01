import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/record_repository.dart';
import '../../../domain/models/attachment.dart';
import '../../../domain/models/timeline_record.dart';
import '../../media/domain/media_service.dart';
import '../../media/presentation/media_preview.dart';
import '../../timeline/application/timeline_controller.dart';
import '../../timeline/presentation/timeline_card.dart';
import 'delete_record_button.dart';

class RecordDetailPage extends StatefulWidget {
  const RecordDetailPage({
    super.key,
    required this.recordId,
    this.repository,
    this.mediaService,
    this.queueOrphanCleanup,
    this.timelineController,
  });

  final String recordId;
  final RecordRepository? repository;
  final MediaService? mediaService;
  final OrphanCleanupQueue? queueOrphanCleanup;
  final TimelineController? timelineController;

  @override
  State<RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends State<RecordDetailPage> {
  TimelineRecord? _record;
  bool _loading = true;
  bool _failed = false;
  var _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RecordDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recordId != widget.recordId ||
        oldWidget.repository != widget.repository) {
      _record = null;
      _load();
    }
  }

  Future<void> _load() async {
    final requestGeneration = ++_requestGeneration;
    final requestedId = widget.recordId;
    final repository = widget.repository;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final record = repository == null
          ? null
          : await repository.get(requestedId);
      if (!_isCurrentRequest(requestGeneration, requestedId, repository)) {
        return;
      }
      setState(() {
        _record = record;
        _loading = false;
      });
    } catch (_) {
      if (!_isCurrentRequest(requestGeneration, requestedId, repository)) {
        return;
      }
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  bool _isCurrentRequest(
    int generation,
    String recordId,
    RecordRepository? repository,
  ) =>
      mounted &&
      generation == _requestGeneration &&
      recordId == widget.recordId &&
      repository == widget.repository;

  @override
  Widget build(BuildContext context) {
    final record = _record;
    return Scaffold(
      appBar: AppBar(title: const Text('记录详情')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('无法读取记录，请重试'),
                  TextButton(onPressed: _load, child: const Text('重试')),
                ],
              ),
            )
          : record == null
          ? const Center(child: Text('记录不存在'))
          : _RecordDetail(
              record: record,
              onEdit: () => _edit(record),
              deleteButton: _deleteButton(record),
            ),
    );
  }

  Widget _deleteButton(TimelineRecord record) {
    final repository = widget.repository;
    final mediaService = widget.mediaService;
    final queueOrphanCleanup = widget.queueOrphanCleanup;
    if (repository == null ||
        mediaService == null ||
        queueOrphanCleanup == null) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.delete_outline),
        label: const Text('删除'),
      );
    }
    return DeleteRecordButton(
      recordId: record.id,
      repository: repository,
      mediaService: mediaService,
      queueOrphanCleanup: queueOrphanCleanup,
      onDeleted: () async {
        await widget.timelineController?.reload();
        if (mounted) context.pop(true);
      },
    );
  }

  Future<void> _edit(TimelineRecord record) async {
    final updated = await context.push<bool>('/records/${record.id}/edit');
    if (updated != true || !mounted) return;
    await Future.wait([
      _load(),
      widget.timelineController?.reload() ?? Future.value(),
    ]);
  }
}

class _RecordDetail extends StatelessWidget {
  const _RecordDetail({
    required this.record,
    required this.onEdit,
    required this.deleteButton,
  });

  final TimelineRecord record;
  final VoidCallback onEdit;
  final Widget deleteButton;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        recordSummary(record),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      Text(_dateTimeLabel(record.occurredAt)),
      if (record.note?.trim().isNotEmpty == true) ...[
        const SizedBox(height: 16),
        Text(record.note!),
      ],
      if (record.details case GrowthDetails(
        :final heightCm,
        :final weightKg,
        :final headCm,
      )) ...[
        const SizedBox(height: 24),
        if (heightCm != null)
          _DetailValue(label: '身高', value: '${_number(heightCm)} cm'),
        if (weightKg != null)
          _DetailValue(label: '体重', value: '${_number(weightKg)} kg'),
        if (headCm != null)
          _DetailValue(label: '头围', value: '${_number(headCm)} cm'),
      ],
      if (record.attachments.isNotEmpty) ...[
        const SizedBox(height: 24),
        for (final attachment in record.attachments)
          _AttachmentPreview(attachment: attachment),
      ],
      const SizedBox(height: 32),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('编辑'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: deleteButton),
        ],
      ),
    ],
  );
}

class _DetailValue extends StatelessWidget {
  const _DetailValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [Text(label), const Spacer(), Text(value)]),
  );
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: MediaPreview(
      filePath: attachment.filePath,
      thumbnailPath: attachment.thumbnailPath,
      mediaType: attachment.mediaType,
      width: double.infinity,
      height: 160,
    ),
  );
}

String _dateTimeLabel(DateTime instant) {
  final local = instant.toLocal();
  return '${local.year}年${local.month}月${local.day}日 '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();
