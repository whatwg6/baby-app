import 'dart:async';
import 'dart:io';

import 'package:baby_growth_timeline/domain/models/attachment.dart';
import 'package:baby_growth_timeline/features/media/data/local_media_service.dart';
import 'package:baby_growth_timeline/features/media/domain/media_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory picker;

  String uuidFor(int index) =>
      '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('baby-media-support-');
    picker = await Directory.systemTemp.createTemp('baby-media-picker-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
    if (await picker.exists()) await picker.delete(recursive: true);
  });

  LocalMediaService createService({
    Directory? supportRoot,
    String Function()? createId,
    Future<List<int>> Function(String sourcePath, int maxDimension)?
    imageThumbnailer,
    Future<List<int>> Function(String sourcePath, int maxDimension)?
    videoThumbnailer,
    Future<void> Function(File source, File destination)? copyFile,
    Future<void> Function(File source, String destinationPath)? moveFile,
    Future<void> Function(File file)? claimFile,
    Future<DateTime> Function(File file)? lastModified,
    DateTime Function()? now,
    Duration orphanGracePeriod = const Duration(minutes: 10),
  }) {
    var nextId = 0;
    return LocalMediaService(
      applicationSupportDirectory: () async => supportRoot ?? root,
      createId: createId ?? () => uuidFor(nextId++),
      imageThumbnailer: imageThumbnailer ?? (_, _) async => <int>[1, 2, 3],
      videoThumbnailer: videoThumbnailer ?? (_, _) async => <int>[4, 5, 6],
      copyFile: copyFile,
      moveFile: moveFile,
      claimFile: claimFile,
      lastModified: lastModified,
      now: now,
      orphanGracePeriod: orphanGracePeriod,
    );
  }

  Future<File> source(String name) async =>
      File(p.join(picker.path, name)).writeAsBytes(<int>[7, 8, 9]);

  test(
    'stage accepts only the allowlist and canonicalizes extensions',
    () async {
      final service = createService();
      final cases = <(String, MediaType, String)>[
        ('one.JPG', MediaType.image, '.jpg'),
        ('two.JPEG', MediaType.image, '.jpeg'),
        ('three.PNG', MediaType.image, '.png'),
        ('four.HEIC', MediaType.image, '.heic'),
        ('five.WEBP', MediaType.image, '.webp'),
        ('six.MP4', MediaType.video, '.mp4'),
        ('seven.MOV', MediaType.video, '.mov'),
      ];

      for (final (name, type, extension) in cases) {
        final input = await source(name);
        final staged = await service.stage(
          PickedMedia(sourcePath: input.path, mediaType: type),
        );

        expect(p.extension(staged.stagingPath), extension);
        expect(p.extension(staged.finalPath), extension);
        expect(
          p.basenameWithoutExtension(staged.finalPath),
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-'
              r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
        expect(
          staged.stagingPath,
          contains('${p.separator}staging${p.separator}'),
        );
        expect(
          staged.finalPath,
          contains('${p.separator}media${p.separator}originals${p.separator}'),
        );
        expect(await File(staged.stagingPath).readAsBytes(), <int>[7, 8, 9]);
        expect(p.extension(staged.thumbnailFinalPath!), '.jpg');
        await service.rollback(staged);
      }

      final unsupported = await source('animation.gif');
      await expectLater(
        service.stage(
          PickedMedia(sourcePath: unsupported.path, mediaType: MediaType.image),
        ),
        throwsA(isA<UnsupportedMediaException>()),
      );

      final mismatched = await source('movie.mp4');
      await expectLater(
        service.stage(
          PickedMedia(sourcePath: mismatched.path, mediaType: MediaType.image),
        ),
        throwsA(isA<UnsupportedMediaException>()),
      );
    },
  );

  test(
    'stage creates image and first-frame video thumbnails in staging',
    () async {
      final generatedFrom = <String>[];
      final service = createService(
        imageThumbnailer: (path, maxDimension) async {
          generatedFrom.add('image:$maxDimension:$path');
          return <int>[11];
        },
        videoThumbnailer: (path, maxDimension) async {
          generatedFrom.add('video:$maxDimension:$path');
          return <int>[22];
        },
      );
      final photo = await source('photo.jpg');
      final video = await source('clip.mov');

      final stagedPhoto = await service.stage(
        PickedMedia(sourcePath: photo.path, mediaType: MediaType.image),
      );
      final stagedVideo = await service.stage(
        PickedMedia(sourcePath: video.path, mediaType: MediaType.video),
      );

      expect(generatedFrom, <String>[
        'image:1200:${stagedPhoto.stagingPath}',
        'video:1200:${stagedVideo.stagingPath}',
      ]);
      expect(await File(stagedPhoto.thumbnailStagingPath!).readAsBytes(), <int>[
        11,
      ]);
      expect(await File(stagedVideo.thumbnailStagingPath!).readAsBytes(), <int>[
        22,
      ]);
    },
  );

  test(
    'an insufficient-space copy failure removes the partial staging file',
    () async {
      final input = await source('large.jpg');
      final service = createService(
        copyFile: (source, destination) async {
          await destination.writeAsBytes(<int>[1]);
          throw const FileSystemException('No space left on device');
        },
      );

      await expectLater(
        service.stage(
          PickedMedia(sourcePath: input.path, mediaType: MediaType.image),
        ),
        throwsA(isA<MediaStorageException>()),
      );

      final staging = Directory(p.join(root.path, 'staging'));
      expect(
        await staging.exists()
            ? await staging.list().toList()
            : <FileSystemEntity>[],
        isEmpty,
      );
    },
  );

  test(
    'a late original staging collision preserves the foreign file',
    () async {
      final input = await source('photo.jpg');
      final service = createService(
        claimFile: (file) async {
          await file.writeAsBytes(<int>[91], flush: true);
          await file.create(exclusive: true);
        },
      );
      final foreignPath = p.join(root.path, 'staging', '${uuidFor(0)}.jpg');

      await expectLater(
        service.stage(
          PickedMedia(sourcePath: input.path, mediaType: MediaType.image),
        ),
        throwsA(isA<MediaStorageException>()),
      );

      expect(await File(foreignPath).readAsBytes(), <int>[91]);
    },
  );

  test(
    'a late thumbnail staging collision cleans the owned original only',
    () async {
      var claims = 0;
      final input = await source('photo.jpg');
      final service = createService(
        claimFile: (file) async {
          claims += 1;
          if (claims == 1) {
            await file.create(exclusive: true);
            return;
          }
          await file.writeAsBytes(<int>[92], flush: true);
          await file.create(exclusive: true);
        },
      );
      final originalPath = p.join(root.path, 'staging', '${uuidFor(0)}.jpg');
      final foreignThumbnailPath = p.join(
        root.path,
        'staging',
        '${uuidFor(0)}-thumb.jpg',
      );

      await expectLater(
        service.stage(
          PickedMedia(sourcePath: input.path, mediaType: MediaType.image),
        ),
        throwsA(isA<MediaStorageException>()),
      );

      expect(await File(originalPath).exists(), isFalse);
      expect(await File(foreignThumbnailPath).readAsBytes(), <int>[92]);
    },
  );

  test('fitWithinDimensions bounds landscape and portrait longest edges', () {
    expect(
      fitWithinDimensions(
        const MediaDimensions(width: 2400, height: 1200),
        1200,
      ),
      const MediaDimensions(width: 1200, height: 600),
    );
    expect(
      fitWithinDimensions(
        const MediaDimensions(width: 1200, height: 2400),
        1200,
      ),
      const MediaDimensions(width: 600, height: 1200),
    );
    expect(
      fitWithinDimensions(const MediaDimensions(width: 800, height: 600), 1200),
      const MediaDimensions(width: 800, height: 600),
    );
  });

  test(
    'commit and rollback are idempotent across staged and final paths',
    () async {
      final service = createService();
      final input = await source('photo.jpg');
      final staged = await service.stage(
        PickedMedia(sourcePath: input.path, mediaType: MediaType.image),
      );

      final first = await service.commit(staged);
      final second = await service.commit(staged);

      expect(second, first);
      expect(await File(first.filePath).exists(), isTrue);
      expect(await File(first.thumbnailPath!).exists(), isTrue);
      expect(await File(staged.stagingPath).exists(), isFalse);

      await service.rollback(staged);
      await service.rollback(staged);

      expect(await File(first.filePath).exists(), isFalse);
      expect(await File(first.thumbnailPath!).exists(), isFalse);
    },
  );

  test(
    'a partial commit compensates the original and remaining staging files',
    () async {
      var moves = 0;
      final service = createService(
        moveFile: (source, destinationPath) async {
          moves += 1;
          if (moves == 2) {
            throw const FileSystemException('thumbnail move failed');
          }
          await source.rename(destinationPath);
        },
      );
      final input = await source('photo.jpg');
      final staged = await service.stage(
        PickedMedia(sourcePath: input.path, mediaType: MediaType.image),
      );

      await expectLater(
        service.commit(staged),
        throwsA(isA<MediaStorageException>()),
      );

      expect(await File(staged.stagingPath).exists(), isFalse);
      expect(await File(staged.thumbnailStagingPath!).exists(), isFalse);
      expect(await File(staged.finalPath).exists(), isFalse);
      expect(await File(staged.thumbnailFinalPath!).exists(), isFalse);
    },
  );

  test('rollback ignores paths not owned by this service', () async {
    final service = createService();
    final victim = await source('outside.jpg');
    final malicious = StagedMedia(
      stagingPath: victim.path,
      finalPath: victim.path,
      mediaType: MediaType.image,
      thumbnailStagingPath: victim.path,
      thumbnailFinalPath: victim.path,
    );

    await service.rollback(malicious);

    expect(await victim.exists(), isTrue);
  });

  test(
    'stage rejects a final-path collision without deleting the existing file',
    () async {
      final originals = Directory(p.join(root.path, 'media', 'originals'));
      await originals.create(recursive: true);
      final existing = await File(
        p.join(originals.path, '${uuidFor(0)}.jpg'),
      ).writeAsBytes(<int>[99]);
      final input = await source('photo.jpg');
      final service = createService();

      await expectLater(
        service.stage(
          PickedMedia(sourcePath: input.path, mediaType: MediaType.image),
        ),
        throwsA(isA<MediaStorageException>()),
      );

      expect(await existing.readAsBytes(), <int>[99]);
    },
  );

  test('an invalid injected ID is replaced by a canonical UUID name', () async {
    final service = createService(createId: () => '../not-a-uuid');
    final input = await source('photo.JPG');

    final staged = await service.stage(
      PickedMedia(sourcePath: input.path, mediaType: MediaType.image),
    );

    expect(p.extension(staged.finalPath), '.jpg');
    expect(
      p.basenameWithoutExtension(staged.finalPath),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-'
          r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test(
    'commit rejects a destination created after stage without adopting it',
    () async {
      final input = await source('photo.jpg');
      final service = createService();
      final staged = await service.stage(
        PickedMedia(sourcePath: input.path, mediaType: MediaType.image),
      );
      final foreign = await File(
        staged.finalPath,
      ).writeAsBytes(<int>[99], flush: true);

      await expectLater(
        service.commit(staged),
        throwsA(isA<MediaStorageException>()),
      );

      expect(await foreign.readAsBytes(), <int>[99]);
      expect(await File(staged.stagingPath).exists(), isFalse);
      expect(await File(staged.thumbnailStagingPath!).exists(), isFalse);
    },
  );

  test(
    'a late thumbnail collision preserves the foreign file and compensates the original',
    () async {
      final input = await source('photo.jpg');
      final service = createService();
      final staged = await service.stage(
        PickedMedia(sourcePath: input.path, mediaType: MediaType.image),
      );
      final foreignThumbnail = await File(
        staged.thumbnailFinalPath!,
      ).writeAsBytes(<int>[88], flush: true);

      await expectLater(
        service.commit(staged),
        throwsA(isA<MediaStorageException>()),
      );

      expect(await File(staged.finalPath).exists(), isFalse);
      expect(await foreignThumbnail.readAsBytes(), <int>[88]);
    },
  );

  test(
    'removeOrphans preserves every referenced original and thumbnail',
    () async {
      final service = createService();
      final keepSource = await source('keep.jpg');
      final removeSource = await source('remove.mov');
      final stagedKeep = await service.stage(
        PickedMedia(sourcePath: keepSource.path, mediaType: MediaType.image),
      );
      final keep = await service.commit(stagedKeep);
      final stagedOrphan = await service.stage(
        PickedMedia(sourcePath: removeSource.path, mediaType: MediaType.video),
      );
      final orphan = await service.commit(stagedOrphan);
      service.releaseOwnership(<StagedMedia>[stagedKeep, stagedOrphan]);
      final stale = DateTime(2026, 7, 31);
      await File(orphan.filePath).setLastModified(stale);
      await File(orphan.thumbnailPath!).setLastModified(stale);

      await service.removeOrphans(<String>{keep.filePath, keep.thumbnailPath!});

      expect(await File(keep.filePath).exists(), isTrue);
      expect(await File(keep.thumbnailPath!).exists(), isTrue);
      expect(await File(orphan.filePath).exists(), isFalse);
      expect(await File(orphan.thumbnailPath!).exists(), isFalse);
    },
  );

  test(
    'removeOrphans leaves fresh active files and removes stale staging',
    () async {
      final clock = DateTime(2026, 8, 1, 12);
      final service = createService(now: () => clock);
      final input = await source('active.jpg');
      final active = await service.stage(
        PickedMedia(sourcePath: input.path, mediaType: MediaType.image),
      );
      await File(active.stagingPath).setLastModified(clock);
      await File(active.thumbnailStagingPath!).setLastModified(clock);
      final oldStaging = await File(
        p.join(root.path, 'staging', 'crash-leftover.jpg'),
      ).writeAsBytes(<int>[1]);
      await oldStaging.setLastModified(
        clock.subtract(const Duration(hours: 1)),
      );
      final freshFinal = await File(
        p.join(root.path, 'media', 'originals', 'fresh.jpg'),
      ).writeAsBytes(<int>[2]);
      await freshFinal.setLastModified(clock);

      await service.removeOrphans(const <String>{});

      expect(await File(active.stagingPath).exists(), isTrue);
      expect(await File(active.thumbnailStagingPath!).exists(), isTrue);
      expect(await oldStaging.exists(), isFalse);
      expect(await freshFinal.exists(), isTrue);
    },
  );

  test(
    'removeOrphans from another service preserves a stale active stage',
    () async {
      final clock = DateTime(2030, 8, 1, 12);
      final owner = createService(now: () => clock);
      final cleaner = createService(now: () => clock);
      final input = await source('active.jpg');
      final active = await owner.stage(
        PickedMedia(sourcePath: input.path, mediaType: MediaType.image),
      );
      final stale = clock.subtract(const Duration(hours: 1));
      await File(active.stagingPath).setLastModified(stale);
      await File(active.thumbnailStagingPath!).setLastModified(stale);

      await cleaner.removeOrphans(const <String>{});

      expect(await File(active.stagingPath).exists(), isTrue);
      expect(await File(active.thumbnailStagingPath!).exists(), isTrue);
    },
  );

  test(
    'cleanup concurrent with finalization preserves pre-reference files',
    () async {
      final moveStarted = Completer<void>();
      final allowMove = Completer<void>();
      var pauseFirstMove = true;
      final clock = DateTime(2030, 8, 1, 12);
      final owner = createService(
        now: () => clock,
        moveFile: (source, destinationPath) async {
          if (pauseFirstMove) {
            pauseFirstMove = false;
            moveStarted.complete();
            await allowMove.future;
          }
          await source.rename(destinationPath);
        },
      );
      final cleaner = createService(now: () => clock);
      final input = await source('active.jpg');
      final active = await owner.stage(
        PickedMedia(sourcePath: input.path, mediaType: MediaType.image),
      );
      final stale = clock.subtract(const Duration(hours: 1));
      await File(active.stagingPath).setLastModified(stale);
      await File(active.thumbnailStagingPath!).setLastModified(stale);

      final commit = owner.commit(active);
      await moveStarted.future;
      final cleanup = cleaner.removeOrphans(const <String>{});
      await Future<void>.delayed(Duration.zero);
      allowMove.complete();
      final committed = await commit;
      await cleanup;

      expect(await File(committed.filePath).exists(), isTrue);
      expect(await File(committed.thumbnailPath!).exists(), isTrue);
    },
  );

  test(
    'cleanup epoch protects a save acquired and released during the scan',
    () async {
      final originals = Directory(p.join(root.path, 'media', 'originals'));
      final thumbnails = Directory(p.join(root.path, 'media', 'thumbnails'));
      await originals.create(recursive: true);
      await thumbnails.create(recursive: true);
      final blocker = await File(
        p.join(originals.path, 'blocker.jpg'),
      ).writeAsBytes(<int>[1]);
      await blocker.setLastModified(DateTime(2020));
      final scanPaused = Completer<void>();
      final allowScan = Completer<void>();
      var paused = false;
      final clock = DateTime(2030, 8, 1, 12);
      final cleaner = createService(
        now: () => clock,
        lastModified: (file) async {
          if (!paused && p.basename(file.path) == 'blocker.jpg') {
            paused = true;
            scanPaused.complete();
            await allowScan.future;
          }
          return file.lastModified();
        },
      );
      final owner = createService(now: () => clock);

      final firstCleanup = cleaner.removeOrphans(const <String>{});
      await scanPaused.future;
      final input = await source('active.jpg');
      final staged = await owner.stage(
        PickedMedia(sourcePath: input.path, mediaType: MediaType.image),
      );
      final committed = await owner.commit(staged);
      await File(committed.filePath).setLastModified(DateTime(2020));
      await File(committed.thumbnailPath!).setLastModified(DateTime(2020));
      owner.releaseOwnership(<StagedMedia>[staged]);
      allowScan.complete();
      await firstCleanup;

      expect(await File(committed.filePath).exists(), isTrue);
      expect(await File(committed.thumbnailPath!).exists(), isTrue);

      await cleaner.removeOrphans(<String>{
        committed.filePath,
        committed.thumbnailPath!,
      });
      expect(await File(committed.filePath).exists(), isTrue);
      expect(await File(committed.thumbnailPath!).exists(), isTrue);

      await cleaner.removeOrphans(const <String>{});
      expect(await File(committed.filePath).exists(), isFalse);
      expect(await File(committed.thumbnailPath!).exists(), isFalse);
    },
  );

  test('stage rejects a symlinked application-support root', () async {
    final external = await Directory.systemTemp.createTemp(
      'baby-media-external-',
    );
    addTearDown(() async {
      if (await external.exists()) await external.delete(recursive: true);
    });
    final supportLink = Link(p.join(picker.path, 'support-link'));
    await supportLink.create(external.path);
    final service = createService(supportRoot: Directory(supportLink.path));
    final input = await source('photo.jpg');

    await expectLater(
      service.stage(
        PickedMedia(sourcePath: input.path, mediaType: MediaType.image),
      ),
      throwsA(isA<MediaStorageException>()),
    );

    expect(await external.list().toList(), isEmpty);
  });

  test('stage rejects symlinked staging and media directories', () async {
    final external = await Directory.systemTemp.createTemp(
      'baby-media-external-',
    );
    addTearDown(() async {
      if (await external.exists()) await external.delete(recursive: true);
    });
    final stagingLink = Link(p.join(root.path, 'staging'));
    await stagingLink.create(external.path);
    final service = createService();
    final input = await source('photo.jpg');

    await expectLater(
      service.stage(
        PickedMedia(sourcePath: input.path, mediaType: MediaType.image),
      ),
      throwsA(isA<MediaStorageException>()),
    );
    expect(await external.list().toList(), isEmpty);

    await stagingLink.delete();
    final mediaLink = Link(p.join(root.path, 'media'));
    await mediaLink.create(external.path);
    await expectLater(
      service.stage(
        PickedMedia(sourcePath: input.path, mediaType: MediaType.image),
      ),
      throwsA(isA<MediaStorageException>()),
    );
    expect(await external.list().toList(), isEmpty);
  });

  test('remove refuses a media symlink without touching its target', () async {
    final originals = Directory(p.join(root.path, 'media', 'originals'));
    await originals.create(recursive: true);
    final external = await File(
      p.join(picker.path, 'external.jpg'),
    ).writeAsBytes(<int>[77]);
    final escape = Link(p.join(originals.path, 'escape.jpg'));
    await escape.create(external.path);

    await createService().remove(<String>[escape.path]);

    expect(await escape.exists(), isTrue);
    expect(await external.readAsBytes(), <int>[77]);
  });

  test('removeOrphans refuses a symlinked media traversal root', () async {
    final external = await Directory.systemTemp.createTemp(
      'baby-media-external-',
    );
    addTearDown(() async {
      if (await external.exists()) await external.delete(recursive: true);
    });
    final originals = Directory(p.join(external.path, 'originals'));
    await originals.create();
    final victim = await File(
      p.join(originals.path, 'victim.jpg'),
    ).writeAsBytes(<int>[66]);
    await victim.setLastModified(DateTime(2020));
    await Link(p.join(root.path, 'media')).create(external.path);

    await expectLater(
      createService(now: () => DateTime(2030)).removeOrphans(const <String>{}),
      throwsA(isA<MediaStorageException>()),
    );

    expect(await victim.readAsBytes(), <int>[66]);
  });
}
