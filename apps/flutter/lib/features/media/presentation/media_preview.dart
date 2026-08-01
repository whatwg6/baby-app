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
    this.width = 88,
    this.height = 88,
  });

  final String filePath;
  final String? thumbnailPath;
  final MediaType mediaType;
  final ImageProvider<Object>? imageProvider;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (!File(filePath).existsSync()) {
      return _UnavailableMedia(width: width, height: height);
    }
    final previewPath = mediaType == MediaType.video
        ? thumbnailPath
        : thumbnailPath ?? filePath;
    if (previewPath == null || !File(previewPath).existsSync()) {
      return _UnavailableMedia(width: width, height: height);
    }
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image(
              image: imageProvider ?? FileImage(File(previewPath)),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) =>
                  _UnavailableMedia(width: width, height: height),
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
