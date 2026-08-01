import '../../../domain/models/attachment.dart';

abstract interface class MediaService {
  Future<StagedMedia> stage(PickedMedia input);

  Future<CommittedMedia> commit(StagedMedia staged);

  Future<void> rollback(StagedMedia staged);

  Future<void> remove(Iterable<String> paths);

  Future<void> removeOrphans(Set<String> referencedPaths);
}

/// Lets a coordinator release rollback ownership after durable DB commit.
abstract interface class MediaLifecycleOwnership {
  void releaseOwnership(Iterable<StagedMedia> staged);
}

class PickedMedia {
  const PickedMedia({required this.sourcePath, required this.mediaType});

  final String sourcePath;
  final MediaType mediaType;
}

class StagedMedia {
  const StagedMedia({
    required this.stagingPath,
    required this.finalPath,
    required this.mediaType,
    this.thumbnailStagingPath,
    this.thumbnailFinalPath,
  });

  final String stagingPath;
  final String finalPath;
  final MediaType mediaType;
  final String? thumbnailStagingPath;
  final String? thumbnailFinalPath;
}

class CommittedMedia {
  const CommittedMedia({required this.filePath, this.thumbnailPath});

  final String filePath;
  final String? thumbnailPath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommittedMedia &&
          filePath == other.filePath &&
          thumbnailPath == other.thumbnailPath;

  @override
  int get hashCode => Object.hash(filePath, thumbnailPath);
}

class UnsupportedMediaException implements Exception {
  const UnsupportedMediaException(this.path);

  final String path;

  @override
  String toString() => 'UnsupportedMediaException: $path';
}

class MediaStorageException implements Exception {
  const MediaStorageException(this.operation, [this.cause]);

  final String operation;
  final Object? cause;

  @override
  String toString() => 'MediaStorageException($operation): $cause';
}
