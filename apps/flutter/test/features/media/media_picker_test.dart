import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baby_growth_timeline/domain/models/attachment.dart';
import 'package:baby_growth_timeline/domain/models/baby.dart';
import 'package:baby_growth_timeline/features/baby/presentation/baby_form.dart';
import 'package:baby_growth_timeline/features/media/domain/media_service.dart';
import 'package:baby_growth_timeline/features/media/presentation/media_picker.dart';
import 'package:baby_growth_timeline/features/media/presentation/media_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPicker(
    WidgetTester tester, {
    required MediaPickerAdapter adapter,
    required ValueChanged<PickedMedia> onPicked,
    Set<MediaType> allowedTypes = const <MediaType>{MediaType.image},
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaPicker(
          adapter: adapter,
          allowedTypes: allowedTypes,
          onPicked: onPicked,
        ),
      ),
    ),
  );

  testWidgets('canceling the platform picker is silent', (tester) async {
    final picked = <PickedMedia>[];
    await pumpPicker(
      tester,
      adapter: _PickerAdapter(result: null),
      onPicked: picked.add,
    );

    await tester.tap(find.byKey(const Key('pick-image')));
    await tester.pump();

    expect(picked, isEmpty);
    expect(find.text('请在系统设置中允许访问照片'), findsNothing);
    expect(find.text('无法选择媒体，请重试'), findsNothing);
  });

  testWidgets('photo permission denial displays actionable settings guidance', (
    tester,
  ) async {
    final picked = <PickedMedia>[];
    await pumpPicker(
      tester,
      adapter: _PickerAdapter(
        error: PlatformException(code: 'photo_access_denied'),
      ),
      onPicked: picked.add,
    );

    await tester.tap(find.byKey(const Key('pick-image')));
    await tester.pump();

    expect(picked, isEmpty);
    expect(find.text('请在系统设置中允许访问照片'), findsOneWidget);
  });

  testWidgets('the picker exposes only the media types allowed by its form', (
    tester,
  ) async {
    await pumpPicker(
      tester,
      adapter: _PickerAdapter(result: '/picker/a.jpg'),
      allowedTypes: const <MediaType>{MediaType.image, MediaType.video},
      onPicked: (_) {},
    );
    expect(find.byKey(const Key('pick-image')), findsOneWidget);
    expect(find.byKey(const Key('pick-video')), findsOneWidget);

    await pumpPicker(
      tester,
      adapter: _PickerAdapter(result: '/picker/a.jpg'),
      onPicked: (_) {},
    );
    expect(find.byKey(const Key('pick-image')), findsOneWidget);
    expect(find.byKey(const Key('pick-video')), findsNothing);
  });

  testWidgets(
    'missing and undecodable media render the unavailable placeholder',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('media-preview-');
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final corrupt = File('${temp.path}${Platform.pathSeparator}corrupt.jpg')
        ..writeAsStringSync('not an image');
      final failingProvider = _FailingImageProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              MediaPreview(
                filePath: '${temp.path}${Platform.pathSeparator}missing.jpg',
                mediaType: MediaType.image,
              ),
              MediaPreview(
                filePath: corrupt.path,
                mediaType: MediaType.image,
                imageProvider: failingProvider,
              ),
            ],
          ),
        ),
      );
      failingProvider.fail();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('媒体文件不可用'), findsNWidgets(2));
    },
  );

  testWidgets(
    'missing originals stay unavailable even when a thumbnail exists',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('media-preview-');
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final thumbnail =
          File('${temp.path}${Platform.pathSeparator}thumbnail.jpg')
            ..writeAsBytesSync(
              base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lE'
                'QVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
              ),
            );

      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              MediaPreview(
                filePath: '${temp.path}${Platform.pathSeparator}missing.jpg',
                thumbnailPath: thumbnail.path,
                mediaType: MediaType.image,
              ),
              MediaPreview(
                filePath: '${temp.path}${Platform.pathSeparator}missing.mp4',
                thumbnailPath: thumbnail.path,
                mediaType: MediaType.video,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('媒体文件不可用'), findsNWidgets(2));
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    },
  );

  testWidgets(
    'avatar replacement saves the new path before removing the old file',
    (tester) async {
      final events = <String>[];
      final media = _AvatarMediaService(events);
      BabyDraft? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BabyForm(
              initialValue: Baby(
                id: 'baby-1',
                name: '安安',
                birthDate: '2025-06-15',
                avatarPath: '/support/media/originals/old.jpg',
                createdAt: DateTime.utc(2025, 6, 15),
                updatedAt: DateTime.utc(2025, 6, 15),
              ),
              mediaService: media,
              mediaPickerAdapter: _PickerAdapter(result: '/picker/new.jpg'),
              onSave: (draft) async {
                saved = draft;
                events.add('baby:save:${draft.avatarPath}');
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('pick-image')));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(saved!.avatarPath, '/support/media/originals/avatar.jpg');
      expect(events, <String>[
        'files:stage',
        'files:commit',
        'baby:save:/support/media/originals/avatar.jpg',
        'files:release',
        'files:remove:/support/media/thumbnails/avatar.jpg,'
            '/support/media/originals/old.jpg',
      ]);
    },
  );

  testWidgets(
    'a failed avatar save rolls back the new file and keeps the old one',
    (tester) async {
      final events = <String>[];
      final media = _AvatarMediaService(events);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BabyForm(
              initialValue: Baby(
                id: 'baby-1',
                name: '安安',
                birthDate: '2025-06-15',
                avatarPath: '/support/media/originals/old.jpg',
                createdAt: DateTime.utc(2025, 6, 15),
                updatedAt: DateTime.utc(2025, 6, 15),
              ),
              mediaService: media,
              mediaPickerAdapter: _PickerAdapter(result: '/picker/new.jpg'),
              onSave: (_) async {
                events.add('baby:save:failed');
                throw StateError('database failed');
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('pick-image')));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(events, <String>[
        'files:stage',
        'files:commit',
        'baby:save:failed',
        'files:rollback',
      ]);
      expect(find.text('保存失败，请稍后重试。'), findsOneWidget);
    },
  );

  testWidgets('post-save UI failure never rolls back a durably saved avatar', (
    tester,
  ) async {
    final events = <String>[];
    final media = _AvatarMediaService(events);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BabyForm(
            initialValue: Baby(
              id: 'baby-1',
              name: '安安',
              birthDate: '2025-06-15',
              avatarPath: '/support/media/originals/old.jpg',
              createdAt: DateTime.utc(2025, 6, 15),
              updatedAt: DateTime.utc(2025, 6, 15),
            ),
            mediaService: media,
            mediaPickerAdapter: _PickerAdapter(result: '/picker/new.jpg'),
            onSave: (draft) async {
              events.add('baby:save:${draft.avatarPath}');
            },
            onSaved: () async {
              events.add('ui:failed');
              throw StateError('navigation failed');
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('pick-image')));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(events, <String>[
      'files:stage',
      'files:commit',
      'baby:save:/support/media/originals/avatar.jpg',
      'files:release',
      'files:remove:/support/media/thumbnails/avatar.jpg,'
          '/support/media/originals/old.jpg',
      'ui:failed',
    ]);
    expect(events, isNot(contains('files:rollback')));
  });

  testWidgets(
    'setup avatar save stays terminal when post-save UI retries fail',
    (tester) async {
      final events = <String>[];
      final media = _AvatarMediaService(events);
      final savedDrafts = <BabyDraft>[];
      var postSaveAttempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BabyForm(
              mediaService: media,
              mediaPickerAdapter: _PickerAdapter(result: '/picker/new.jpg'),
              onSave: (draft) async => savedDrafts.add(draft),
              onSaved: () async {
                postSaveAttempts += 1;
                throw StateError('navigation failed');
              },
            ),
          ),
        ),
      );

      await tester.enterText(find.byKey(const Key('baby-name')), '安安');
      await tester.enterText(find.byKey(const Key('birth-date')), '2025-06-15');
      await tester.tap(find.byKey(const Key('pick-image')));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(savedDrafts, hasLength(1));
      expect(
        savedDrafts.single.avatarPath,
        '/support/media/originals/avatar.jpg',
      );
      expect(find.text('资料已保存，但页面操作失败，请重试。'), findsOneWidget);
      expect(find.text('保存失败，请稍后重试。'), findsNothing);
      expect(find.text('已保存'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      await tester.tap(find.text('重试页面操作'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(savedDrafts, hasLength(1));
      expect(postSaveAttempts, 2);
      expect(
        savedDrafts.single.avatarPath,
        '/support/media/originals/avatar.jpg',
      );
    },
  );

  testWidgets(
    'edit avatar save stays terminal when post-save UI retries fail',
    (tester) async {
      final events = <String>[];
      final media = _AvatarMediaService(events);
      final savedDrafts = <BabyDraft>[];
      var postSaveAttempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BabyForm(
              initialValue: Baby(
                id: 'baby-1',
                name: '安安',
                birthDate: '2025-06-15',
                avatarPath: '/support/media/originals/old.jpg',
                createdAt: DateTime.utc(2025, 6, 15),
                updatedAt: DateTime.utc(2025, 6, 15),
              ),
              mediaService: media,
              mediaPickerAdapter: _PickerAdapter(result: '/picker/new.jpg'),
              onSave: (draft) async => savedDrafts.add(draft),
              onSaved: () async {
                postSaveAttempts += 1;
                throw StateError('refresh failed');
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('pick-image')));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(savedDrafts, hasLength(1));
      expect(
        savedDrafts.single.avatarPath,
        '/support/media/originals/avatar.jpg',
      );
      expect(find.text('资料已保存，但页面操作失败，请重试。'), findsOneWidget);
      expect(find.text('保存失败，请稍后重试。'), findsNothing);
      expect(find.text('已保存'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      await tester.tap(find.text('重试页面操作'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(savedDrafts, hasLength(1));
      expect(postSaveAttempts, 2);
      expect(
        savedDrafts.single.avatarPath,
        '/support/media/originals/avatar.jpg',
      );
    },
  );
}

class _FailingImageProvider extends ImageProvider<Object> {
  final Completer<ImageInfo> _completer = Completer<ImageInfo>();

  void fail() => _completer.completeError(StateError('decode failed'));

  @override
  Future<Object> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<Object>(this);

  @override
  ImageStreamCompleter loadImage(Object key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_completer.future);
}

class _PickerAdapter implements MediaPickerAdapter {
  _PickerAdapter({this.result, this.error});

  final String? result;
  final Object? error;

  @override
  Future<String?> pick(MediaType mediaType) async {
    if (error != null) throw error!;
    return result;
  }
}

class _AvatarMediaService implements MediaService, MediaLifecycleOwnership {
  _AvatarMediaService(this.events);

  final List<String> events;

  @override
  Future<StagedMedia> stage(PickedMedia input) async {
    events.add('files:stage');
    return const StagedMedia(
      stagingPath: '/support/staging/avatar.jpg',
      finalPath: '/support/media/originals/avatar.jpg',
      mediaType: MediaType.image,
      thumbnailStagingPath: '/support/staging/avatar-thumb.jpg',
      thumbnailFinalPath: '/support/media/thumbnails/avatar.jpg',
    );
  }

  @override
  Future<CommittedMedia> commit(StagedMedia staged) async {
    events.add('files:commit');
    return CommittedMedia(
      filePath: staged.finalPath,
      thumbnailPath: staged.thumbnailFinalPath,
    );
  }

  @override
  Future<void> rollback(StagedMedia staged) async {
    events.add('files:rollback');
  }

  @override
  Future<void> remove(Iterable<String> paths) async {
    events.add('files:remove:${paths.join(',')}');
  }

  @override
  Future<void> removeOrphans(Set<String> referencedPaths) async {}

  @override
  void releaseOwnership(Iterable<StagedMedia> staged) {
    events.add('files:release');
  }
}
