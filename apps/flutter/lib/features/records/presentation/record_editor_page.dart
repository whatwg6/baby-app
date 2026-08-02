import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/record_repository.dart';
import '../../../domain/models/record_draft.dart';
import '../../../domain/models/timeline_record.dart';
import '../../media/domain/media_service.dart';
import '../../media/presentation/media_picker.dart';
import '../../media/presentation/media_preview.dart';
import '../application/record_editor_controller.dart';
import 'forms/activity_fields.dart';
import 'forms/growth_fields.dart';
import 'forms/milestone_fields.dart';
import 'forms/moment_fields.dart';

class RecordEditorPage extends StatefulWidget {
  RecordEditorPage({
    super.key,
    required this.type,
    this.recordId,
    this.repository,
    this.controller,
    this.now,
    this.onSaved,
    this.mediaPickerAdapter,
    this.mediaService,
  }) {
    final suppliedController = controller;
    if (suppliedController == null && repository == null) {
      throw ArgumentError(
        'RecordEditorPage requires a controller or repository.',
      );
    }
    if (suppliedController != null && suppliedController.draft.type != type) {
      throw ArgumentError(
        'Controller type ${suppliedController.draft.type.name} does not match '
        'editor type ${type.name}.',
      );
    }
    if (suppliedController != null && suppliedController.recordId != recordId) {
      throw ArgumentError(
        'Controller recordId ${suppliedController.recordId} does not match '
        'editor recordId $recordId.',
      );
    }
  }

  final RecordType type;
  final String? recordId;
  final RecordRepository? repository;
  final RecordEditorController? controller;
  final DateTime Function()? now;
  final MediaPickerAdapter? mediaPickerAdapter;
  final MediaService? mediaService;

  /// When supplied, this callback owns post-save navigation.
  final Future<void> Function()? onSaved;

  @override
  State<RecordEditorPage> createState() => _RecordEditorPageState();
}

class _RecordEditorPageState extends State<RecordEditorPage> {
  late RecordEditorController _controller;
  late final TextEditingController _occurredAtController;
  late final TextEditingController _noteController;
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  late final TextEditingController _headController;
  late final TextEditingController _amountController;
  late final TextEditingController _durationController;
  late final TextEditingController _titleController;
  RecordDetails? _details;
  String? _occurredAtError;
  late String _occurredAtText;
  late String _noteText;
  var _finishingSave = false;
  var _persisted = false;
  String? _postSaveError;
  var _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _occurredAtController = TextEditingController();
    _noteController = TextEditingController();
    _heightController = TextEditingController();
    _weightController = TextEditingController();
    _headController = TextEditingController();
    _amountController = TextEditingController();
    _durationController = TextEditingController();
    _titleController = TextEditingController();
    _controller = _createController();
    _populate(_controller.draft);
    if (widget.recordId != null) _loadExisting();
  }

  @override
  void didUpdateWidget(covariant RecordEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type == widget.type &&
        oldWidget.recordId == widget.recordId &&
        oldWidget.repository == widget.repository &&
        oldWidget.controller == widget.controller &&
        oldWidget.mediaService == widget.mediaService) {
      return;
    }
    _loadGeneration += 1;
    _controller = _createController();
    _occurredAtError = null;
    _finishingSave = false;
    _persisted = false;
    _postSaveError = null;
    _populate(_controller.draft);
    if (widget.recordId != null) _loadExisting();
  }

  RecordEditorController _createController() =>
      widget.controller ??
      RecordEditorController(
        widget.repository!,
        type: widget.type,
        recordId: widget.recordId,
        now: widget.now,
        mediaService: widget.mediaService,
      );

  Future<void> _loadExisting() async {
    final controller = _controller;
    final generation = ++_loadGeneration;
    await controller.load();
    if (mounted &&
        generation == _loadGeneration &&
        identical(controller, _controller)) {
      _populate(controller.draft);
      setState(() {});
    }
  }

  void _populate(RecordDraft draft) {
    _occurredAtText = _formatDateTime(draft.occurredAt);
    _noteText = draft.note ?? '';
    _occurredAtController.text = _occurredAtText;
    _noteController.text = _noteText;
    _heightController.clear();
    _weightController.clear();
    _headController.clear();
    _amountController.clear();
    _durationController.clear();
    _titleController.clear();
    _details = draft.details;
    switch (draft.details) {
      case GrowthDetails(:final heightCm, :final weightKg, :final headCm):
        _heightController.text = _number(heightCm);
        _weightController.text = _number(weightKg);
        _headController.text = _number(headCm);
      case ActivityDetails(:final amount, :final durationMinutes):
        _amountController.text = _number(amount);
        _durationController.text = durationMinutes?.toString() ?? '';
      case MilestoneDetails(:final title):
        _titleController.text = title;
      case null:
        break;
    }
  }

  @override
  void dispose() {
    _occurredAtController.dispose();
    _noteController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _headController.dispose();
    _amountController.dispose();
    _durationController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _setDetails(RecordDetails details) {
    setState(() {
      _details = details;
      _controller.updateDraft(_controller.draft.copyWith(details: details));
    });
  }

  void _updateShared() {
    setState(() {
      _controller.updateDraft(
        _controller.draft.copyWith(note: _noteText, details: _details),
      );
    });
  }

  void _addPickedMedia(PickedMedia media) {
    setState(() {
      _controller.updateDraft(
        _controller.draft.copyWith(
          attachments: <RecordDraftAttachment>[
            ..._controller.draft.attachments,
            RecordDraftAttachment.picked(
              sourcePath: media.sourcePath,
              mediaType: media.mediaType,
            ),
          ],
        ),
      );
    });
  }

  void _removeAttachment(RecordDraftAttachment attachment) {
    setState(() {
      _controller.updateDraft(
        _controller.draft.copyWith(
          attachments: _controller.draft.attachments
              .where((candidate) => !identical(candidate, attachment))
              .toList(),
        ),
      );
    });
  }

  DateTime? _parseOccurredAt() {
    final match = _dateTimePattern.firstMatch(_occurredAtText.trim());
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final parsed = DateTime(year, month, day, hour, minute);
    if (parsed.year != year ||
        parsed.month != month ||
        parsed.day != day ||
        parsed.hour != hour ||
        parsed.minute != minute) {
      return null;
    }
    return parsed;
  }

  Future<void> _submit() async {
    if (_finishingSave) return;
    final occurredAt = _parseOccurredAt();
    if (occurredAt == null) {
      setState(() => _occurredAtError = '请输入有效的发生时间。');
      return;
    }
    _occurredAtError = null;
    final details = _detailsFromFields();
    _controller.updateDraft(
      _controller.draft.copyWith(
        occurredAt: occurredAt,
        note: _noteText,
        details: details,
      ),
    );
    setState(() => _finishingSave = true);
    final submittingController = _controller;
    try {
      final saved = await submittingController.submit();
      if (!mounted ||
          !identical(submittingController, _controller) ||
          saved == null) {
        return;
      }
      setState(() => _persisted = true);
      final afterSave = widget.onSaved;
      if (afterSave != null) {
        try {
          await afterSave();
        } catch (_) {
          if (mounted) {
            setState(() {
              _postSaveError = '记录已保存，但页面刷新失败，请返回后查看。';
            });
          }
        }
        return;
      }
      _navigateAfterSave();
    } finally {
      if (mounted &&
          identical(submittingController, _controller) &&
          !_persisted) {
        setState(() => _finishingSave = false);
      }
    }
  }

  void _navigateAfterSave() {
    if (widget.recordId == null) {
      context.go('/timeline');
    } else {
      context.pop(true);
    }
  }

  RecordDetails? _detailsFromFields() {
    final activity = _details;
    return switch (_controller.draft.type) {
      RecordType.moment => null,
      RecordType.growth => RecordDetails.growth(
        heightCm: activity is GrowthDetails ? activity.heightCm : null,
        weightKg: activity is GrowthDetails ? activity.weightKg : null,
        headCm: activity is GrowthDetails ? activity.headCm : null,
      ),
      RecordType.activity when activity is ActivityDetails =>
        RecordDetails.activity(
          activityType: activity.activityType,
          amount: activity.amount,
          durationMinutes: activity.durationMinutes,
        ),
      RecordType.activity => null,
      RecordType.milestone => activity is MilestoneDetails ? activity : null,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_controller.saveError == '记录不存在' ||
        _controller.saveError == '无法读取记录，请重试') {
      return Scaffold(
        appBar: AppBar(title: const Text('编辑记录')),
        body: Center(child: Text(_controller.saveError!)),
      );
    }
    final disabled = _controller.isSaving || _finishingSave || _persisted;
    final details = _details;
    return Scaffold(
      appBar: AppBar(title: Text(widget.recordId == null ? '添加记录' : '编辑记录')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('occurred-at'),
              controller: _occurredAtController,
              enabled: !disabled,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                labelText: '发生时间',
                hintText: 'yyyy-MM-dd HH:mm',
                errorText: _occurredAtError,
              ),
              onChanged: (value) {
                setState(() {
                  _occurredAtText = value;
                  _occurredAtError = null;
                });
              },
            ),
            const SizedBox(height: 12),
            _buildTypeFields(details, !disabled),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('record-note'),
              controller: _noteController,
              enabled: !disabled,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '备注'),
              onChanged: (value) {
                _noteText = value;
                _updateShared();
              },
            ),
            const SizedBox(height: 12),
            if (_controller.draft.attachments.isNotEmpty) ...[
              Text('已有附件 ${_controller.draft.attachments.length} 个'),
              const SizedBox(height: 8),
              for (final attachment in _controller.draft.attachments)
                _AttachmentRow(
                  attachment: attachment,
                  enabled: !disabled,
                  onRemove: () => _removeAttachment(attachment),
                ),
            ] else
              const Text('尚未添加媒体'),
            if (_controller.validationError != null) ...[
              const SizedBox(height: 12),
              Text(
                _controller.validationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_controller.saveError != null) ...[
              const SizedBox(height: 12),
              Text(
                _controller.saveError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_postSaveError != null) ...[
              const SizedBox(height: 12),
              Text(
                _postSaveError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _navigateAfterSave,
                  child: Text(widget.recordId == null ? '返回时间轴' : '返回详情'),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: disabled ? null : _submit,
              child: Text(
                _persisted
                    ? '已保存'
                    : disabled
                    ? '保存中…'
                    : '保存',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeFields(RecordDetails? details, bool enabled) {
    return switch (_controller.draft.type) {
      RecordType.moment => MomentFields(
        enabled: enabled,
        mediaPickerAdapter: widget.mediaPickerAdapter,
        onPicked: _addPickedMedia,
      ),
      RecordType.growth => GrowthFields(
        heightController: _heightController,
        weightController: _weightController,
        headController: _headController,
        currentDetails: () =>
            _details is GrowthDetails ? _details as GrowthDetails : null,
        enabled: enabled,
        onChanged: _setDetails,
      ),
      RecordType.activity => ActivityFields(
        activityType: details is ActivityDetails ? details.activityType : null,
        currentType: () => _details is ActivityDetails
            ? (_details as ActivityDetails).activityType
            : null,
        amountController: _amountController,
        durationController: _durationController,
        enabled: enabled,
        onChanged: _setDetails,
      ),
      RecordType.milestone => MilestoneFields(
        titleController: _titleController,
        currentDetails: () =>
            _details is MilestoneDetails ? _details as MilestoneDetails : null,
        enabled: enabled,
        onChanged: _setDetails,
        mediaPickerAdapter: widget.mediaPickerAdapter,
        onPicked: _addPickedMedia,
      ),
    };
  }
}

final _dateTimePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$');

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.attachment,
    required this.enabled,
    required this.onRemove,
  });

  final RecordDraftAttachment attachment;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final (mediaType, path, thumbnailPath) = switch (attachment) {
      ExistingAttachment(
        :final mediaType,
        :final filePath,
        :final thumbnailPath,
      ) =>
        (mediaType, filePath, thumbnailPath),
      PickedAttachment(:final mediaType, :final sourcePath) => (
        mediaType,
        sourcePath,
        null,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          MediaPreview(
            filePath: path,
            thumbnailPath: thumbnailPath,
            mediaType: mediaType,
            width: 56,
            height: 56,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _fileName(path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: '移除附件',
            onPressed: enabled ? onRemove : null,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final name = normalized.split('/').last;
  return name.isEmpty ? path : name;
}

String _number(num? value) {
  if (value == null) return '';
  return value == value.roundToDouble() ? value.toInt().toString() : '$value';
}
