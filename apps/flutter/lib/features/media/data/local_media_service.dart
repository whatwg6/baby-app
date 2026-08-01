import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../../domain/models/attachment.dart';
import '../domain/media_service.dart';

typedef ThumbnailGenerator =
    Future<List<int>> Function(String sourcePath, int maxDimension);
typedef MediaFileCopier = Future<void> Function(File source, File destination);
typedef MediaFileMover =
    Future<void> Function(File source, String destinationPath);
typedef MediaFileClaimer = Future<void> Function(File file);
typedef MediaLastModified = Future<DateTime> Function(File file);

class MediaDimensions {
  const MediaDimensions({required this.width, required this.height});

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaDimensions &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => Object.hash(width, height);
}

MediaDimensions fitWithinDimensions(MediaDimensions source, int maxDimension) {
  if (source.width <= 0 || source.height <= 0 || maxDimension <= 0) {
    throw ArgumentError('Dimensions and maxDimension must be positive.');
  }
  final longest = source.width > source.height ? source.width : source.height;
  if (longest <= maxDimension) return source;
  final scale = maxDimension / longest;
  return MediaDimensions(
    width: (source.width * scale).round().clamp(1, maxDimension),
    height: (source.height * scale).round().clamp(1, maxDimension),
  );
}

class LocalMediaService implements MediaService, MediaLifecycleOwnership {
  static const thumbnailMaxDimension = 1200;
  static final Map<String, _RootMediaLeases> _rootLeases =
      <String, _RootMediaLeases>{};

  LocalMediaService({
    Future<Directory> Function()? applicationSupportDirectory,
    String Function()? createId,
    ThumbnailGenerator? imageThumbnailer,
    ThumbnailGenerator? videoThumbnailer,
    MediaFileCopier? copyFile,
    MediaFileMover? moveFile,
    MediaFileClaimer? claimFile,
    MediaLastModified? lastModified,
    DateTime Function()? now,
    this.orphanGracePeriod = const Duration(minutes: 10),
  }) : _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory,
       _createId = createId ?? const Uuid().v4,
       _imageThumbnailer = imageThumbnailer ?? _createImageThumbnail,
       _videoThumbnailer = videoThumbnailer ?? _createVideoThumbnail,
       _copyFile = copyFile ?? _copy,
       _moveFile = moveFile ?? _move,
       _claimFile = claimFile ?? _claim,
       _lastModified = lastModified ?? _readLastModified,
       _now = now ?? DateTime.now;

  static const _imageExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'heic',
    'webp',
  };
  static const _videoExtensions = <String>{'mp4', 'mov'};

  final Future<Directory> Function() _applicationSupportDirectory;
  final String Function() _createId;
  final ThumbnailGenerator _imageThumbnailer;
  final ThumbnailGenerator _videoThumbnailer;
  final MediaFileCopier _copyFile;
  final MediaFileMover _moveFile;
  final MediaFileClaimer _claimFile;
  final MediaLastModified _lastModified;
  final DateTime Function() _now;
  final Duration orphanGracePeriod;
  final Map<String, StagedMedia> _ownedMedia = <String, StagedMedia>{};
  final Map<String, Set<String>> _createdStagingPaths = <String, Set<String>>{};
  final Map<String, Set<String>> _createdFinalPaths = <String, Set<String>>{};
  final Map<String, _RootMediaLeases> _ownedLeases =
      <String, _RootMediaLeases>{};

  @override
  Future<StagedMedia> stage(PickedMedia input) async {
    final extension = p
        .extension(input.sourcePath)
        .replaceFirst('.', '')
        .toLowerCase();
    final allowed = switch (input.mediaType) {
      MediaType.image => _imageExtensions,
      MediaType.video => _videoExtensions,
    };
    if (!allowed.contains(extension)) {
      throw UnsupportedMediaException(input.sourcePath);
    }

    final root = await _validatedRoot('stage');
    final leases = _leasesFor(root.path);
    final stagingDirectory = (await _managedDirectory(
      root.path,
      const <String>['staging'],
      create: true,
      operation: 'stage',
    ))!;
    final originalsDirectory = (await _managedDirectory(
      root.path,
      const <String>['media', 'originals'],
      create: true,
      operation: 'stage',
    ))!;
    final thumbnailsDirectory = (await _managedDirectory(
      root.path,
      const <String>['media', 'thumbnails'],
      create: true,
      operation: 'stage',
    ))!;

    final id = _safeId(_createId());
    final stagingPath = p.join(stagingDirectory.path, '$id.$extension');
    final finalPath = p.join(originalsDirectory.path, '$id.$extension');
    final thumbnailStagingPath = p.join(stagingDirectory.path, '$id-thumb.jpg');
    final thumbnailFinalPath = p.join(thumbnailsDirectory.path, '$id.jpg');
    final staged = StagedMedia(
      stagingPath: stagingPath,
      finalPath: finalPath,
      mediaType: input.mediaType,
      thumbnailStagingPath: thumbnailStagingPath,
      thumbnailFinalPath: thumbnailFinalPath,
    );

    for (final path in <String>[
      stagingPath,
      thumbnailStagingPath,
      finalPath,
      thumbnailFinalPath,
    ]) {
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw MediaStorageException(
          'stage',
          FileSystemException('Media path collision', path),
        );
      }
    }
    _ownedMedia[finalPath] = staged;
    _createdStagingPaths[finalPath] = <String>{};
    _createdFinalPaths[finalPath] = <String>{};
    _ownedLeases[finalPath] = leases;
    leases.acquire(_mediaPaths(staged));

    try {
      await _claimFile(File(stagingPath));
      _createdStagingPaths[finalPath]!.add(stagingPath);
      await _copyFile(File(input.sourcePath), File(stagingPath));
      await _validateFileWithin(
        stagingDirectory.path,
        stagingPath,
        operation: 'stage',
      );
      final bytes = switch (input.mediaType) {
        MediaType.image => await _imageThumbnailer(
          stagingPath,
          thumbnailMaxDimension,
        ),
        MediaType.video => await _videoThumbnailer(
          stagingPath,
          thumbnailMaxDimension,
        ),
      };
      if (bytes.isEmpty) {
        throw const MediaStorageException('thumbnail', 'empty output');
      }
      await _claimFile(File(thumbnailStagingPath));
      _createdStagingPaths[finalPath]!.add(thumbnailStagingPath);
      await File(thumbnailStagingPath).writeAsBytes(bytes, flush: true);
      await _validateFileWithin(
        stagingDirectory.path,
        thumbnailStagingPath,
        operation: 'stage',
      );
      return staged;
    } catch (error) {
      await rollback(staged);
      if (error is MediaStorageException) rethrow;
      throw MediaStorageException('stage', error);
    }
  }

  @override
  Future<CommittedMedia> commit(StagedMedia staged) async {
    if (!_owns(staged)) {
      throw const MediaStorageException('commit', 'unowned staged media');
    }
    final createdFinalPaths = _createdFinalPaths[staged.finalPath]!;
    final rootPath = p.dirname(p.dirname(staged.stagingPath));
    try {
      final stagingDirectory = await _managedDirectory(
        rootPath,
        const <String>['staging'],
        create: false,
        operation: 'commit',
      );
      if (stagingDirectory == null) {
        throw const MediaStorageException('commit', 'staging is missing');
      }
      final originalsDirectory = (await _managedDirectory(
        rootPath,
        const <String>['media', 'originals'],
        create: true,
        operation: 'commit',
      ))!;
      await _moveIfNeeded(
        staged.stagingPath,
        staged.finalPath,
        createdFinalPaths,
        sourceRoot: stagingDirectory.path,
        destinationRoot: originalsDirectory.path,
      );
      final thumbnailStagingPath = staged.thumbnailStagingPath;
      final thumbnailFinalPath = staged.thumbnailFinalPath;
      if (thumbnailStagingPath != null && thumbnailFinalPath != null) {
        final thumbnailsDirectory = (await _managedDirectory(
          rootPath,
          const <String>['media', 'thumbnails'],
          create: true,
          operation: 'commit',
        ))!;
        await _moveIfNeeded(
          thumbnailStagingPath,
          thumbnailFinalPath,
          createdFinalPaths,
          sourceRoot: stagingDirectory.path,
          destinationRoot: thumbnailsDirectory.path,
        );
      }
      return CommittedMedia(
        filePath: staged.finalPath,
        thumbnailPath: staged.thumbnailFinalPath,
      );
    } catch (error) {
      await rollback(staged);
      if (error is MediaStorageException) rethrow;
      throw MediaStorageException('commit', error);
    }
  }

  Future<void> _moveIfNeeded(
    String sourcePath,
    String destinationPath,
    Set<String> createdFinalPaths, {
    required String sourceRoot,
    required String destinationRoot,
  }) async {
    final source = File(sourcePath);
    final destination = File(destinationPath);
    if (createdFinalPaths.contains(destinationPath)) {
      return;
    }
    if (await FileSystemEntity.type(destinationPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw MediaStorageException(
        'commit',
        FileSystemException('Media path collision', destinationPath),
      );
    }
    if (!await _isSafeFileWithin(sourceRoot, sourcePath)) {
      throw MediaStorageException(
        'commit',
        FileSystemException('Staged file is missing or unsafe', sourcePath),
      );
    }
    await destination.create(exclusive: true);
    createdFinalPaths.add(destinationPath);
    await _validateFileWithin(
      destinationRoot,
      destinationPath,
      operation: 'commit',
    );
    await _moveFile(source, destinationPath);
    await _validateFileWithin(
      destinationRoot,
      destinationPath,
      operation: 'commit',
    );
  }

  @override
  Future<void> rollback(StagedMedia staged) async {
    final owned = _ownedMedia[staged.finalPath];
    if (owned == null || !_sameMedia(owned, staged)) return;
    final createdStagingPaths =
        _createdStagingPaths[staged.finalPath] ?? const {};
    final createdFinalPaths = _createdFinalPaths[staged.finalPath] ?? const {};
    final rootPath = p.dirname(p.dirname(owned.stagingPath));
    await _deleteBestEffort(rootPath, <String?>[
      ...createdStagingPaths,
      ...createdFinalPaths,
    ]);
    _releaseLease(owned);
    _ownedMedia.remove(staged.finalPath);
    _createdStagingPaths.remove(staged.finalPath);
    _createdFinalPaths.remove(staged.finalPath);
  }

  @override
  void releaseOwnership(Iterable<StagedMedia> staged) {
    for (final media in staged) {
      if (_owns(media)) {
        _releaseLease(media);
        _ownedMedia.remove(media.finalPath);
        _createdStagingPaths.remove(media.finalPath);
        _createdFinalPaths.remove(media.finalPath);
      }
    }
  }

  @override
  Future<void> remove(Iterable<String> paths) async {
    final root = await _validatedRoot('remove');
    final mediaDirectory = await _managedDirectory(
      root.path,
      const <String>['media'],
      create: false,
      operation: 'remove',
    );
    if (mediaDirectory == null) return;
    final mediaRoot = mediaDirectory.path;
    for (final path in paths) {
      final normalized = p.normalize(p.absolute(path));
      if (!_isWithin(mediaRoot, normalized)) continue;
      if (await _isSafeFileWithin(mediaRoot, normalized)) {
        await File(normalized).delete();
      }
    }
  }

  @override
  Future<void> removeOrphans(Set<String> referencedPaths) async {
    final root = await _validatedRoot('remove orphans');
    final leases = _leasesFor(root.path);
    leases.beginCleanup();
    try {
      final referenced = referencedPaths
          .map((path) => p.normalize(p.absolute(path)))
          .toSet();
      final cutoff = _now().subtract(orphanGracePeriod);
      final mediaDirectories = <Directory?>[
        await _managedDirectory(
          root.path,
          const <String>['media', 'originals'],
          create: false,
          operation: 'remove orphans',
        ),
        await _managedDirectory(
          root.path,
          const <String>['media', 'thumbnails'],
          create: false,
          operation: 'remove orphans',
        ),
      ];
      for (final directory in mediaDirectories.whereType<Directory>()) {
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is File &&
              !referenced.contains(p.normalize(p.absolute(entity.path))) &&
              !_isLeased(entity.path, leases) &&
              await _isSafeFileWithin(directory.path, entity.path) &&
              await _olderThan(entity, cutoff)) {
            if (!_isLeased(entity.path, leases) &&
                await _isSafeFileWithin(directory.path, entity.path)) {
              await entity.delete();
            }
          }
        }
      }

      final staging = await _managedDirectory(
        root.path,
        const <String>['staging'],
        create: false,
        operation: 'remove orphans',
      );
      if (staging != null) {
        await for (final entity in staging.list(followLinks: false)) {
          if (entity is File &&
              !_isLeased(entity.path, leases) &&
              await _isSafeFileWithin(staging.path, entity.path) &&
              await _olderThan(entity, cutoff)) {
            if (!_isLeased(entity.path, leases) &&
                await _isSafeFileWithin(staging.path, entity.path)) {
              await entity.delete();
            }
          }
        }
      }
    } finally {
      leases.endCleanup();
    }
  }

  bool _owns(StagedMedia staged) {
    final owned = _ownedMedia[staged.finalPath];
    return owned != null && _sameMedia(owned, staged);
  }

  static bool _sameMedia(StagedMedia left, StagedMedia right) =>
      left.stagingPath == right.stagingPath &&
      left.finalPath == right.finalPath &&
      left.mediaType == right.mediaType &&
      left.thumbnailStagingPath == right.thumbnailStagingPath &&
      left.thumbnailFinalPath == right.thumbnailFinalPath;

  static _RootMediaLeases _leasesFor(String rootPath) {
    final key = p.normalize(p.absolute(rootPath));
    return _rootLeases.putIfAbsent(key, _RootMediaLeases.new);
  }

  static Set<String> _mediaPaths(StagedMedia staged) => <String?>[
    staged.stagingPath,
    staged.thumbnailStagingPath,
    staged.finalPath,
    staged.thumbnailFinalPath,
  ].whereType<String>().map((path) => p.normalize(p.absolute(path))).toSet();

  void _releaseLease(StagedMedia staged) {
    final leases = _ownedLeases.remove(staged.finalPath);
    leases?.release(_mediaPaths(staged));
  }

  static bool _isLeased(String path, _RootMediaLeases leases) {
    final normalized = p.normalize(p.absolute(path));
    return leases.protects(normalized);
  }

  Future<bool> _olderThan(File file, DateTime cutoff) async =>
      (await _lastModified(file)).isBefore(cutoff);

  static bool _isWithin(String root, String candidate) =>
      candidate == root || p.isWithin(root, candidate);

  Future<Directory> _validatedRoot(String operation) async {
    try {
      final supplied = await _applicationSupportDirectory();
      var type = await FileSystemEntity.type(supplied.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw FileSystemException(
          'Application support root must not be a symlink',
          supplied.path,
        );
      }
      if (type == FileSystemEntityType.notFound) {
        await supplied.create(recursive: true);
        type = await FileSystemEntity.type(supplied.path, followLinks: false);
      }
      if (type != FileSystemEntityType.directory) {
        throw FileSystemException(
          'Application support root is not a directory',
          supplied.path,
        );
      }
      final resolved = p.normalize(
        p.absolute(await supplied.resolveSymbolicLinks()),
      );
      return Directory(resolved);
    } catch (error) {
      if (error is MediaStorageException) rethrow;
      throw MediaStorageException(operation, error);
    }
  }

  static Future<Directory?> _managedDirectory(
    String rootPath,
    List<String> components, {
    required bool create,
    required String operation,
  }) async {
    final canonicalRoot = p.normalize(p.absolute(rootPath));
    var current = canonicalRoot;
    for (final component in components) {
      current = p.join(current, component);
      var type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        if (!create) return null;
        await Directory(current).create();
        type = await FileSystemEntity.type(current, followLinks: false);
      }
      if (type != FileSystemEntityType.directory) {
        throw MediaStorageException(
          operation,
          FileSystemException('Managed directory is unsafe', current),
        );
      }
      final resolved = p.normalize(
        p.absolute(await Directory(current).resolveSymbolicLinks()),
      );
      if (!_isWithin(canonicalRoot, resolved)) {
        throw MediaStorageException(
          operation,
          FileSystemException('Managed directory escapes root', current),
        );
      }
      current = resolved;
    }
    return Directory(current);
  }

  static Future<bool> _isSafeFileWithin(String rootPath, String path) async {
    final root = p.normalize(p.absolute(rootPath));
    final candidate = p.normalize(p.absolute(path));
    if (!_isWithin(root, candidate)) return false;
    if (await FileSystemEntity.type(candidate, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    final resolved = p.normalize(
      p.absolute(await File(candidate).resolveSymbolicLinks()),
    );
    return _isWithin(root, resolved);
  }

  static Future<void> _validateFileWithin(
    String rootPath,
    String path, {
    required String operation,
  }) async {
    if (!await _isSafeFileWithin(rootPath, path)) {
      throw MediaStorageException(
        operation,
        FileSystemException('Media file escapes managed storage', path),
      );
    }
  }

  static String _safeId(String value) {
    final normalized = value.toLowerCase();
    if (Uuid.isValidUUID(fromString: normalized)) return normalized;
    return const Uuid().v4();
  }

  static Future<void> _deleteBestEffort(
    String rootPath,
    Iterable<String?> paths,
  ) async {
    for (final path in paths.whereType<String>().toSet()) {
      try {
        if (await _isSafeFileWithin(rootPath, path)) {
          await File(path).delete();
        }
      } on FileSystemException {
        // Compensation is intentionally idempotent and best-effort.
      }
    }
  }

  static Future<void> _copy(File source, File destination) async {
    await source.copy(destination.path);
  }

  static Future<void> _move(File source, String destinationPath) async {
    await source.rename(destinationPath);
  }

  static Future<void> _claim(File file) async {
    await file.create(exclusive: true);
  }

  static Future<DateTime> _readLastModified(File file) => file.lastModified();

  static Future<List<int>> _createImageThumbnail(
    String sourcePath,
    int maxDimension,
  ) async {
    final sourceBytes = await File(sourcePath).readAsBytes();
    final sourceDimensions = await _decodeDimensions(sourceBytes);
    final target = fitWithinDimensions(sourceDimensions, maxDimension);
    final bytes = await FlutterImageCompress.compressWithFile(
      sourcePath,
      minWidth: target.width,
      minHeight: target.height,
      quality: 82,
      format: CompressFormat.jpeg,
      keepExif: true,
    );
    if (bytes == null) {
      throw const MediaStorageException('image thumbnail', 'decode failed');
    }
    return bytes;
  }

  static Future<List<int>> _createVideoThumbnail(
    String sourcePath,
    int maxDimension,
  ) async {
    final frame = await VideoThumbnail.thumbnailData(
      video: sourcePath,
      imageFormat: ImageFormat.JPEG,
      quality: 82,
      timeMs: 0,
    );
    if (frame == null) {
      throw const MediaStorageException('video thumbnail', 'decode failed');
    }
    final sourceDimensions = await _decodeDimensions(frame);
    final target = fitWithinDimensions(sourceDimensions, maxDimension);
    return FlutterImageCompress.compressWithList(
      frame,
      minWidth: target.width,
      minHeight: target.height,
      quality: 82,
      format: CompressFormat.jpeg,
    );
  }

  static Future<MediaDimensions> _decodeDimensions(List<int> bytes) async {
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    try {
      final frame = await codec.getNextFrame();
      try {
        return MediaDimensions(
          width: frame.image.width,
          height: frame.image.height,
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}

class _RootMediaLeases {
  final Set<String> paths = <String>{};
  final Set<String> _cleanupProtectedPaths = <String>{};
  var _activeCleanups = 0;

  void acquire(Set<String> acquiredPaths) {
    paths.addAll(acquiredPaths);
    if (_activeCleanups > 0) {
      _cleanupProtectedPaths.addAll(acquiredPaths);
    }
  }

  void release(Set<String> releasedPaths) {
    paths.removeAll(releasedPaths);
  }

  void beginCleanup() {
    _activeCleanups += 1;
    _cleanupProtectedPaths.addAll(paths);
  }

  void endCleanup() {
    _activeCleanups -= 1;
    if (_activeCleanups == 0) _cleanupProtectedPaths.clear();
  }

  bool protects(String path) =>
      paths.contains(path) || _cleanupProtectedPaths.contains(path);
}
