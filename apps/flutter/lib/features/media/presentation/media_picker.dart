import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../domain/models/attachment.dart';
import '../domain/media_service.dart';

abstract interface class MediaPickerAdapter {
  Future<String?> pick(MediaType mediaType);
}

class ImagePickerMediaAdapter implements MediaPickerAdapter {
  ImagePickerMediaAdapter({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> pick(MediaType mediaType) async {
    final file = switch (mediaType) {
      MediaType.image => await _picker.pickImage(source: ImageSource.gallery),
      MediaType.video => await _picker.pickVideo(source: ImageSource.gallery),
    };
    return file?.path;
  }
}

class MediaPicker extends StatefulWidget {
  const MediaPicker({
    super.key,
    required this.allowedTypes,
    required this.onPicked,
    this.adapter,
    this.enabled = true,
  });

  final Set<MediaType> allowedTypes;
  final ValueChanged<PickedMedia> onPicked;
  final MediaPickerAdapter? adapter;
  final bool enabled;

  @override
  State<MediaPicker> createState() => _MediaPickerState();
}

class _MediaPickerState extends State<MediaPicker> {
  late MediaPickerAdapter _adapter;
  String? _error;
  var _picking = false;

  @override
  void initState() {
    super.initState();
    _adapter = widget.adapter ?? ImagePickerMediaAdapter();
  }

  @override
  void didUpdateWidget(covariant MediaPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adapter != widget.adapter && widget.adapter != null) {
      _adapter = widget.adapter!;
    }
  }

  Future<void> _pick(MediaType mediaType) async {
    if (_picking || !widget.enabled) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final path = await _adapter.pick(mediaType);
      if (path != null && mounted) {
        widget.onPicked(PickedMedia(sourcePath: path, mediaType: mediaType));
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _error = _isPermissionDenial(error) ? '请在系统设置中允许访问照片' : '无法选择媒体，请重试';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法选择媒体，请重试');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  bool _isPermissionDenial(PlatformException error) {
    final code = error.code.toLowerCase();
    return code.contains('denied') ||
        code.contains('restricted') ||
        code.contains('permission');
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && !_picking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            if (widget.allowedTypes.contains(MediaType.image))
              OutlinedButton.icon(
                key: const Key('pick-image'),
                onPressed: enabled ? () => _pick(MediaType.image) : null,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('选择图片'),
              ),
            if (widget.allowedTypes.contains(MediaType.video))
              OutlinedButton.icon(
                key: const Key('pick-video'),
                onPressed: enabled ? () => _pick(MediaType.video) : null,
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('选择视频'),
              ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
