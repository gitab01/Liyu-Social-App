import 'dart:async';

import 'package:liyu_social/core/offline/write_queue.dart';
import 'package:liyu_social/data/local/local_queries.dart';
import 'package:liyu_social/data/local/local_store.dart';
import 'package:liyu_social/data/local/local_watch.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/media.dart';
import 'package:liyu_social/domain/models/story.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';
import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// Stories, including the client-side half of expiry.
///
/// An expired story is not merely hidden from the rail: the sweeper deletes the
/// document and releases its media, mirroring the scheduled cleanup function in
/// the Firebase build. Hiding is not expiring.
class LocalStoryRepository implements StoryRepository {
  LocalStoryRepository({
    required LocalStore store,
    required LocalQueries queries,
    required LocalWriteQueue queue,
    required Future<void> Function(String mediaId) deleteMedia,
    Duration Function()? sweepInterval,
  })  : _store = store,
        _queries = queries,
        _queue = queue,
        _deleteMedia = deleteMedia {
    _sweeper = Timer.periodic(sweepInterval?.call() ?? const Duration(minutes: 5), (_) => unawaited(clearExpired()));
  }

  final LocalStore _store;
  final LocalQueries _queries;
  final LocalWriteQueue _queue;
  final Future<void> Function(String mediaId) _deleteMedia;
  late final Timer _sweeper;

  @override
  Stream<List<Story>> watchActive({required String uid}) => watchCollections<List<Story>>(
    _store,
    const ['stories', 'follows', 'users'],
    () {
      final now = DateTime.now();
      final visible = _queries.followingOf(uid).union({uid});
      final blocking = _queries.blockingOf(uid);
      return _queries
          .storiesSortedAsc()
          .where((story) => visible.contains(story.authorUid))
          .where((story) => !blocking.contains(story.authorUid))
          .where((story) => !story.isExpiredAt(now))
          .toList();
    },
  );

  @override
  Future<Story> publish({
    required UserProfileRef author,
    required MediaRef media,
    String caption = '',
    Duration ttl = const Duration(hours: 24),
  }) {
    final now = DateTime.now();
    final story = Story(
      storyId: _uuid.v4(),
      authorUid: author.uid,
      authorName: author.displayName,
      authorPhoto: author.photoUrl,
      media: media,
      caption: caption,
      createdAt: now,
      expiresAt: now.add(ttl),
    );

    return _queue.enqueue(QueueKind.storyPublish, 'story ${story.storyId}', () async {
      await _store.put('stories', story.storyId, story.toMap());
      return story;
    });
  }

  @override
  Future<void> markViewed({required String storyId, required String uid}) async {
    final doc = _store.doc('stories', storyId);
    if (doc == null) return;
    final story = Story.fromMap(doc);
    if (story.isSeenBy(uid)) return;
    await _store.update('stories', storyId, {
      'viewerUids': [...story.viewerUids, uid],
    });
  }

  Future<void> clearExpired({DateTime? now}) async {
    final at = now ?? DateTime.now();
    for (final story in _queries.storiesSortedAsc()) {
      if (!story.isExpiredAt(at)) continue;
      await _store.delete('stories', story.storyId);
      await _deleteMedia(story.media.id);
    }
  }

  void dispose() => _sweeper.cancel();
}
