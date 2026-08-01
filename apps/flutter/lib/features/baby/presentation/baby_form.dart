import 'package:flutter/material.dart';

import '../../../core/errors/app_exception.dart';
import '../../../domain/models/attachment.dart';
import '../../../domain/models/baby.dart';
import '../../../domain/validation/baby_validator.dart';
import '../../media/data/local_media_service.dart';
import '../../media/domain/media_service.dart';
import '../../media/presentation/media_picker.dart';
import '../../media/presentation/media_preview.dart';

typedef BirthDateSelector =
    Future<DateTime?> Function(
      BuildContext context,
      DateTime initialDate,
      DateTime lastDate,
    );

class BabyForm extends StatefulWidget {
  const BabyForm({
    super.key,
    this.initialValue,
    required this.onSave,
    this.now,
    this.selectBirthDate,
    this.mediaService,
    this.mediaPickerAdapter,
    this.onSaved,
  });

  final Baby? initialValue;
  final Future<void> Function(BabyDraft draft) onSave;
  final DateTime Function()? now;
  final BirthDateSelector? selectBirthDate;
  final MediaService? mediaService;
  final MediaPickerAdapter? mediaPickerAdapter;
  final Future<void> Function()? onSaved;

  @override
  State<BabyForm> createState() => _BabyFormState();
}

class _BabyFormState extends State<BabyForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _birthDateController;
  String? _nameError;
  String? _birthDateError;
  String? _saveError;
  String? _postSaveError;
  var _saving = false;
  var _persisted = false;
  var _retryingPostSave = false;
  late final MediaService _mediaService;
  PickedMedia? _pickedAvatar;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialValue?.name);
    _birthDateController = TextEditingController(
      text: widget.initialValue?.birthDate,
    );
    _mediaService = widget.mediaService ?? LocalMediaService();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  DateTime get _now => (widget.now ?? DateTime.now)().toLocal();

  Future<void> _save() async {
    if (_saving || _persisted) return;
    final draft = BabyDraft(
      name: _nameController.text,
      birthDate: _birthDateController.text,
      sex: widget.initialValue?.sex,
      avatarPath: widget.initialValue?.avatarPath,
    );
    setState(() {
      _nameError = null;
      _birthDateError = null;
      _saveError = null;
      _postSaveError = null;
    });
    try {
      validateBabyDraft(draft, now: _now);
    } on ValidationException catch (error) {
      setState(() {
        if (error.field == 'name') {
          _nameError = error.message;
        } else if (error.field == 'birthDate') {
          _birthDateError = error.message;
        } else {
          _saveError = error.message;
        }
      });
      return;
    }

    setState(() => _saving = true);
    try {
      await _saveWithAvatar(draft);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saveError = '保存失败，请稍后重试。';
          _saving = false;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _persisted = true;
      _saving = false;
    });
    await _runPostSave();
  }

  Future<void> _saveWithAvatar(BabyDraft draft) async {
    final pickedAvatar = _pickedAvatar;
    if (pickedAvatar == null) {
      await widget.onSave(draft);
      return;
    }

    StagedMedia? staged;
    var persisted = false;
    final oldAvatar = widget.initialValue?.avatarPath;
    try {
      staged = await _mediaService.stage(pickedAvatar);
      final committed = await _mediaService.commit(staged);
      await widget.onSave(draft.copyWith(avatarPath: committed.filePath));
      persisted = true;
      try {
        if (_mediaService case final MediaLifecycleOwnership owner) {
          owner.releaseOwnership(<StagedMedia>[staged]);
        }
      } catch (_) {
        // The profile is durable; orphan cleanup can reclaim stale leases later.
      }
      final cleanupPaths = <String?>[
        committed.thumbnailPath,
        if (oldAvatar != committed.filePath) oldAvatar,
      ].whereType<String>().toList();
      if (cleanupPaths.isNotEmpty) {
        try {
          await _mediaService.remove(cleanupPaths);
        } catch (_) {
          // The profile already references the new file; orphan cleanup can retry.
        }
      }
      _pickedAvatar = null;
    } finally {
      if (!persisted && staged != null) {
        await _mediaService.rollback(staged);
      }
    }
  }

  Future<void> _runPostSave() async {
    final onSaved = widget.onSaved;
    if (onSaved == null) return;
    try {
      await onSaved();
    } catch (_) {
      if (mounted) {
        setState(() {
          _postSaveError = '资料已保存，但页面操作失败，请重试。';
        });
      }
    }
  }

  Future<void> _retryPostSave() async {
    if (!_persisted || _retryingPostSave || widget.onSaved == null) return;
    setState(() {
      _retryingPostSave = true;
      _postSaveError = null;
    });
    await _runPostSave();
    if (mounted) setState(() => _retryingPostSave = false);
  }

  Future<void> _pickBirthDate() async {
    final initialDate = _birthDateController.text.isEmpty
        ? _now
        : DateTime.tryParse(_birthDateController.text) ?? _now;
    final selector = widget.selectBirthDate ?? _showDatePicker;
    final selected = await selector(context, initialDate, _now);
    if (selected != null && mounted) {
      setState(() {
        _birthDateController.text = _formatDate(selected);
        _birthDateError = null;
      });
    }
  }

  Future<DateTime?> _showDatePicker(
    BuildContext context,
    DateTime initialDate,
    DateTime lastDate,
  ) {
    final safeInitialDate = initialDate.isAfter(lastDate)
        ? lastDate
        : initialDate;
    return showDatePicker(
      context: context,
      initialDate: safeInitialDate,
      firstDate: DateTime(1900),
      lastDate: lastDate,
    );
  }

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final disabled = _saving || _persisted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const Key('baby-name'),
          controller: _nameController,
          enabled: !disabled,
          decoration: InputDecoration(labelText: '宝宝姓名', errorText: _nameError),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('birth-date'),
          controller: _birthDateController,
          enabled: !disabled,
          keyboardType: TextInputType.datetime,
          decoration: InputDecoration(
            labelText: '生日',
            hintText: 'yyyy-MM-dd',
            errorText: _birthDateError,
            suffixIcon: IconButton(
              tooltip: '选择生日',
              onPressed: disabled ? null : _pickBirthDate,
              icon: const Icon(Icons.calendar_today_outlined),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_pickedAvatar case final picked?) ...[
          MediaPreview(
            filePath: picked.sourcePath,
            mediaType: picked.mediaType,
          ),
          const SizedBox(height: 8),
        ] else if (widget.initialValue?.avatarPath case final avatarPath?) ...[
          MediaPreview(filePath: avatarPath, mediaType: MediaType.image),
          const SizedBox(height: 8),
        ],
        MediaPicker(
          allowedTypes: const <MediaType>{MediaType.image},
          adapter: widget.mediaPickerAdapter,
          enabled: !disabled,
          onPicked: (picked) => setState(() => _pickedAvatar = picked),
        ),
        if (_saveError != null) ...[
          const SizedBox(height: 12),
          Text(
            _saveError!,
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
              onPressed: _retryingPostSave ? null : _retryPostSave,
              child: Text(_retryingPostSave ? '重试中…' : '重试页面操作'),
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: disabled ? null : _save,
          child: Text(
            _persisted
                ? '已保存'
                : _saving
                ? '保存中…'
                : '保存',
          ),
        ),
      ],
    );
  }
}
