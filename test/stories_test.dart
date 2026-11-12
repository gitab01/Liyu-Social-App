import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/data/media/media_store.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/media.dart';
import 'package:liyu_social/domain/models/story.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

import 'helpers/test_backend.dart';

/// Stories have to actually die. A rail that only hides an expired story leaves
/// the bytes on the account forever, which is the opposite of what a metered
/// user is paying for.
void main() {
  late TestBackend backend;
  late StoryRepository stories;
  late MediaStore media;
  late String uid;

  setUp(() async {
    backend = await TestBackend.open();
    uid = await backend.signInAsDemo();
    stories = backend.repository(storyRepositoryProvider);
    media = backend.container.read(mediaStoreProvider);
  });

  tearDown(() => backend.dispose());

  late final author = UserProfileRef(uid: uid, displayName: 'Selam Bekele');

  Future<Story> publishWithMedia(String mediaId, Duration ttl) async {
    // The bytes the story points at, under the same keys the local media
    // service would have written them to.
    media.put('full:$mediaId', Uint8List.fromList([1, 2, 3]));
    media.put('thumbnail:$mediaId', Uint8List.fromList([4, 5]));
    return stories.publish(
      author: author,
      media: MediaRef(id: mediaId),
      caption: 'morning coffee',
      ttl: ttl,
    );
  }

  test('a fresh story is on the rail and its media resolves', () async {
    final story = await publishWithMedia('users/u_selam/story/fresh', const Duration(hours: 4));

    expect(story.expiresAt.isAfter(DateTime.now()), isTrue);
    expect(media.contains('full:users/u_selam/story/fresh'), isTrue);

    final visible = await stories.watchActive(uid: uid).first;
    expect(visible.map((s) => s.storyId), contains(story.storyId));
  });

  test('an expired story leaves the rail and is deleted with its media', () async {
    final story = await publishWithMedia('users/u_selam/story/dead', const Duration(milliseconds: -1));
    final stored = 'full:users/u_selam/story/dead';
    expect(media.contains(stored), isTrue);

    final visible = await stories.watchActive(uid: uid).first;
    expect(visible.map((s) => s.storyId), isNot(contains(story.storyId)));

    await backend.stories.clearExpired();

    expect(backend.store.doc('stories', story.storyId), isNull);
    expect(media.contains(stored), isFalse);
    expect(media.contains('thumbnail:users/u_selam/story/dead'), isFalse);
  });

  test('marking a story viewed records the reader once', () async {
    final story = await publishWithMedia('users/u_selam/story/seen', const Duration(hours: 2));

    await stories.markViewed(storyId: story.storyId, uid: 'u_hiwot');
    await stories.markViewed(storyId: story.storyId, uid: 'u_hiwot');

    final stored = Story.fromMap(backend.store.doc('stories', story.storyId)!);
    expect(stored.viewerUids, {'u_hiwot'});
    expect(stored.isSeenBy('u_hiwot'), isTrue);
    expect(stored.isSeenBy(uid), isFalse);
  });
}
