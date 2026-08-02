import 'dart:io';

import 'package:flutter/material.dart';

import '../../../domain/models/attachment.dart';

class MediaPreview extends StatelessWidget {
  const MediaPreview({
    super.key,
    required this.filePath,
    required this.mediaType,
    this.thumbnailPath,
    this.imageProvider,
    this.unavailableBuilder,
    this.width = 88,
    this.height = 88,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  final String filePath;
  final String? thumbnailPath;
  final MediaType mediaType;
  final ImageProvider<Object>? imageProvider;
  final WidgetBuilder? unavailableBuilder;
  final double width;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    if (!File(filePath).existsSync()) {
      return _buildUnavailable(context);
    }
    final previewPath = mediaType == MediaType.video
        ? thumbnailPath
        : thumbnailPath ?? filePath;
    if (previewPath == null || !File(previewPath).existsSync()) {
      return _buildUnavailable(context);
    }
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: borderRadius,
            child: Image(
              image: imageProvider ?? FileImage(File(previewPath)),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) =>
                  _buildUnavailable(context),
            ),
          ),
          if (mediaType == MediaType.video)
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.play_arrow, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUnavailable(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child:
        unavailableBuilder?.call(context) ??
        _UnavailableMedia(width: width, height: height),
  );
}

class _UnavailableMedia extends StatelessWidget {
  const _UnavailableMedia({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Padding(
      padding: EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_outlined, size: 20),
          SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, child: Text('媒体文件不可用', maxLines: 1)),
        ],
      ),
    ),
  );
}
