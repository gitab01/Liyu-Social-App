import 'package:liyu_social/core/offline/write_queue.dart';
import 'package:liyu_social/data/local/local_counters.dart';
import 'package:liyu_social/data/local/local_queries.dart';
import 'package:liyu_social/data/local/local_store.dart';
import 'package:liyu_social/data/local/local_watch.dart';
import 'package:liyu_social/domain/access_rules.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/media.dart';
import 'package:liyu_social/domain/models/notification.dart';
import 'package:liyu_social/domain/models/post.dart';
import 'package:liyu_social/domain/models/user.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';
import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// Feed reads and writes against the on-device store.
///
/// Two decisions carry the product story. Visibility is evaluated in Dart on
/// every emission — Firestore rules cannot run a follower or block check per
/// document inside a query, but here the repository is the gate, so a
/// followers-only post really is hidden from accounts with no follow edge and a
/// block hides content both ways. And no list is unbounded: the live head takes
/// `limit` rows, `loadOlder` seeks past a `(createdAt, id)` cursor, which is
/// what keeps a scroll from reading the whole collection.
class LocalFeedRepository implements FeedRepository {
  LocalFeedRepository({
    required LocalStore store,
    required LocalQueries queries,
    required LocalCounters counters,
    required LocalWriteQueue queue,
  })  : _store = store,
        _queries = queries,
        _counters = counters,
        _queue = queue;

  final LocalStore _store;
  final LocalQueries _queries;
  final LocalCounters _counters;
  final LocalWriteQueue _queue;

  @override
  Stream<List<Post>> watchFeed({int limit = 12}) => watchCollections<List<Post>>(
    _store,
    const ['posts', 'follows', 'users'],
    () => _visible().take(limit).toList(),
  );

  @override
  Stream<List<Post>> watchAuthorPosts(String authorUid, {int limit = 30}) => watchCollections<List<Post>>(
    _store,
    const ['posts', 'follows', 'users'],
    () => _visible().where((p) => p.authorUid == authorUid).take(limit).toList(),
  );

  @override
  Future<List<Post>> loadOlder({required PostCursor cursor, int limit = 12}) async {
    final older = _visible().where((post) => _isOlderThan(post, cursor)).toList();
    return older.take(limit).toList();
  }

  @override
  Future<Post?> loadPost(String postId) async {
    final doc = _store.doc('posts', postId);
    if (doc == null) return null;
    final post = Post.fromMap(doc);
    final viewer = _store.sessionUid;
    if (viewer != null &&
        !AccessRules.canReadPost(
          post: post,
          viewerUid: viewer,
          viewerBlocking: _queries.blockingOf(viewer),
          authorBlocking: _queries.blockingOf(post.authorUid),
          viewerFollowsAuthor: _queries.follows(followerUid: viewer, followingUid: post.authorUid),
        )) {
      throw StateError('permission-denied: this post is not visible to you');
    }
    return post;
  }

  @override
  Future<Post> publish({
    required UserProfileRef author,
    List<MediaRef> media = const [],
    String caption = '',
    Audience audience = Audience.everyone,
    List<String> mentions = const [],
  }) async {
    final post = Post(
      postId: _uuid.v4(),
      authorUid: author.uid,
      authorName: author.displayName,
      authorPhoto: author.photoUrl,
      caption: caption,
      media: media,
      audience: audience,
      createdAt: DateTime.now(),
    );

    // The media landed before this was called, so the only write left is the
    // document — and offline it goes through the queue rather than being lost.
    return _queue.enqueue(QueueKind.postPublish, 'post ${post.postId}', () async {
      await _store.put('posts', post.postId, post.toMap());
      await _counters.onPostAdded(author.uid);
      for (final mentioned in mentions) {
        await _notifyMention(post: post, author: author, mentionedUid: mentioned);
      }
      return post;
    });
  }

  @override
  Future<void> deletePost(String postId) async {
    final doc = _store.doc('posts', postId);
    if (doc == null) return;
    final post = Post.fromMap(doc);
    if (!AccessRules.canWritePost(post: post, uid: _store.sessionUid ?? '')) {
      throw StateError('only the author may delete a post');
    }

    // A post owns its thread and its votes: leaving them behind would keep a
    // comment count alive against a document that no longer exists.
    for (final comment in _queries.commentsFor(postId)) {
      await _store.delete('comments', comment.commentId);
    }
    for (final reaction in _store.all('reactions').where((doc) => doc['postId'] == postId).toList()) {
      await _store.delete('reactions', '${postId}_${reaction['uid']}');
    }
    await _store.delete('posts', postId);
    await _counters.onPostDeleted(post);
  }

  @override
  Future<String?> toggleReaction({required String postId, required String uid, String emoji = 'like'}) async {
    final id = '${postId}_$uid';
    final existing = _store.doc('reactions', id);
    final post = Post.fromMap(_store.doc('posts', postId)!);

    if (!AccessRules.canReadPost(
      post: post,
      viewerUid: uid,
      viewerBlocking: _queries.blockingOf(uid),
      authorBlocking: _queries.blockingOf(post.authorUid),
      viewerFollowsAuthor: _queries.follows(followerUid: uid, followingUid: post.authorUid),
    )) {
      throw StateError('permission-denied: cannot react to this post');
    }

    if (existing != null) {
      await _store.delete('reactions', id);
      await _counters.onReaction(postId, -1);
      return null;
    }

    await _store.put('reactions', id, {
      'postId': postId,
      'uid': uid,
      'emoji': emoji,
      'createdAt': DateTime.now(),
    });
    await _counters.onReaction(postId, 1);

    if (post.authorUid != uid) {
      final actor = _queries.user(uid);
      await _counters.notify(
        notification: AppNotification(
          id: _uuid.v4(),
          recipientUid: post.authorUid,
          type: NotificationType.like,
          actorName: actor?.displayName ?? 'Someone',
          actorUid: uid,
          actorPhoto: actor?.photoUrl,
          body: 'liked your post',
          postId: postId,
          createdAt: DateTime.now(),
        ),
      );
    }
    return emoji;
  }

  @override
  Stream<String?> watchMyReaction({required String postId, required String uid}) =>
      watchCollections<String?>(_store, const ['reactions'], () => _queries.myReactionEmoji(postId: postId, uid: uid));

  @override
  Stream<List<Comment>> watchComments(String postId) =>
      watchCollections<List<Comment>>(_store, const ['comments'], () => _queries.commentsFor(postId));

  @override
  Future<Comment> addComment({
    required Post post,
    required UserProfileRef author,
    required String text,
    List<String> mentions = const [],
  }) async {
    final viewer = _queries.user(author.uid);
    // Commenting requires being able to see the post at all, so a
    // followers-only thread cannot be widened by someone never let in.
    final allowed = AccessRules.canCommentOn(
      post: post,
      viewerUid: author.uid,
      viewerBlocking: viewer?.blocking ?? const {},
      authorBlocking: _queries.blockingOf(post.authorUid),
      viewerFollowsAuthor: _queries.follows(followerUid: author.uid, followingUid: post.authorUid),
    );
    if (!allowed) throw StateError('permission-denied: cannot comment on this post');

    final comment = Comment(
      commentId: _uuid.v4(),
      postId: post.postId,
      authorUid: author.uid,
      authorName: author.displayName,
      authorPhoto: author.photoUrl,
      text: text.trim(),
      mentions: mentions,
      createdAt: DateTime.now(),
    );

    await _store.put('comments', comment.commentId, comment.toMap());
    await _counters.onComment(post.postId, 1);

    if (post.authorUid != author.uid) {
      await _counters.notify(
        notification: AppNotification(
          id: _uuid.v4(),
          recipientUid: post.authorUid,
          type: NotificationType.comment,
          actorName: author.displayName,
          actorUid: author.uid,
          actorPhoto: author.photoUrl,
          body: comment.text,
          postId: post.postId,
          commentId: comment.commentId,
          createdAt: DateTime.now(),
        ),
      );
    }
    for (final mentioned in mentions.where((uid) => uid != post.authorUid)) {
      await _counters.notify(
        notification: AppNotification(
          id: _uuid.v4(),
          recipientUid: mentioned,
          type: NotificationType.mention,
          actorName: author.displayName,
          actorUid: author.uid,
          body: 'mentioned you in a comment',
          postId: post.postId,
          commentId: comment.commentId,
          createdAt: DateTime.now(),
        ),
      );
    }
    return comment;
  }

  @override
  Stream<List<UserProfile>> suggestions({int limit = 8}) => watchCollections<List<UserProfile>>(
    _store,
    const ['follows', 'users'],
    () {
      final viewer = _store.sessionUid;
      if (viewer == null) return const [];
      final following = _queries.followingOf(viewer);
      final blocked = _queries.blockingOf(viewer);
      return _queries
          .allUsers()
          .where((u) => u.uid != viewer && !following.contains(u.uid) && !blocked.contains(u.uid))
          .toList()
        ..sort((a, b) => b.followersCount.compareTo(a.followersCount));
    },
  ).map((users) => users.take(limit).toList());

  List<Post> _visible() => _queries.visiblePosts(viewerUid: _store.sessionUid);

  /// Strictly older than the cursor: time first, then id, matching the sort so a
  /// page boundary can neither repeat nor skip a post.
  bool _isOlderThan(Post post, PostCursor cursor) {
    if (post.createdAt.isBefore(cursor.createdAt)) return true;
    if (post.createdAt.isAfter(cursor.createdAt)) return false;
    return post.postId.compareTo(cursor.postId) < 0;
  }

  Future<void> _notifyMention({
    required Post post,
    required UserProfileRef author,
    required String mentionedUid,
  }) {
    if (mentionedUid == author.uid) return Future.value();
    return _counters.notify(
      notification: AppNotification(
        id: _uuid.v4(),
        recipientUid: mentionedUid,
        type: NotificationType.mention,
        actorName: author.displayName,
        actorUid: author.uid,
        body: 'mentioned you',
        postId: post.postId,
        createdAt: DateTime.now(),
      ),
    );
  }
}
