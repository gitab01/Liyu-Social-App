import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:liyu_social/data/firebase/converters.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/media.dart';
import 'package:liyu_social/domain/models/post.dart';
import 'package:liyu_social/domain/models/user.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// Feed reads and writes against `posts`, with reactions and comments as
/// subcollections.
///
/// Three deliberate choices live here. First, the list queries filter to
/// `audience == 'everyone'`: Firestore cannot evaluate a per-document follower
/// check inside a `list` rule, so a followers-only post is readable by document
/// `get` but never returned by a feed scan — see `firestore.rules`. Second, the
/// shared counters (`likesCount`, `commentsCount`) are written here only at
/// their zero default; every mutation belongs to Cloud Functions, and the rules
/// reject a client that tries to move them. Third, a reaction is one document
/// keyed by the reader's uid, so `watchMyReaction` is a single doc read and the
/// count stays authoritative on the post.
class FirestoreFeedRepository implements FeedRepository {
  FirestoreFeedRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _posts => _firestore.collection('posts');

  @override
  Stream<List<Post>> watchFeed({int limit = 12}) {
    return _publicPostsQuery().orderBy('createdAt', descending: true).limit(limit).snapshots().map(_postsFrom);
  }

  @override
  Stream<List<Post>> watchAuthorPosts(String authorUid, {int limit = 30}) {
    return _posts
        .where('audience', isEqualTo: Audience.everyone.name)
        .where('authorUid', isEqualTo: authorUid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(_postsFrom);
  }

  @override
  Future<List<Post>> loadOlder({required PostCursor cursor, int limit = 12}) async {
    // A (createdAt, postId) pair is what Firestore can seek on. `postId` is the
    // tiebreaker so two posts published in the same millisecond still page in a
    // stable order and the boundary never repeats or skips a row.
    final snap = await _publicPostsQuery()
        .orderBy('createdAt', descending: true)
        .orderBy('postId', descending: true)
        .startAfter([Timestamp.fromDate(cursor.createdAt), cursor.postId])
        .limit(limit)
        .get();
    return _postsFrom(snap);
  }

  @override
  Future<Post> publish({
    required UserProfileRef author,
    List<MediaRef> media = const [],
    String caption = '',
    Audience audience = Audience.everyone,
    List<String> mentions = const [],
  }) async {
    final doc = _posts.doc();
    final post = Post(
      postId: doc.id,
      authorUid: author.uid,
      authorName: author.displayName,
      authorPhoto: author.photoUrl,
      caption: caption,
      media: media,
      audience: audience,
      createdAt: DateTime.now(),
    );
    final data = withTimestamps(post.toMap());
    // Mentions ride on the document so the mention-notification function does not
    // re-parse text; the audience and counters are already at their defaults.
    data['mentions'] = mentions;
    await doc.set(data);
    return post;
  }

  @override
  Future<void> deletePost(String postId) async {
    // A post owns its thread and its reactions: leaving them behind would both
    // bill for orphaned documents and let a stale comment keep a `commentsCount`
    // increment alive against a post that no longer exists.
    final post = _posts.doc(postId);
    final batch = _firestore.batch();
    final comments = await post.collection('comments').get();
    for (final doc in comments.docs) {
      batch.delete(doc.reference);
    }
    final reactions = await post.collection('reactions').get();
    for (final doc in reactions.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(post);
    await batch.commit();
  }

  @override
  Future<String?> toggleReaction({required String postId, required String uid, String emoji = 'like'}) async {
    final doc = _posts.doc(postId).collection('reactions').doc(uid);
    final existing = await doc.get();
    if (existing.exists) {
      await doc.delete();
      return null;
    }
    final reaction = Reaction(postId: postId, uid: uid, emoji: emoji, createdAt: DateTime.now());
    await doc.set(withTimestamps(reaction.toMap()));
    return emoji;
  }

  @override
  Stream<String?> watchMyReaction({required String postId, required String uid}) {
    return _posts.doc(postId).collection('reactions').doc(uid).snapshots().map((snap) {
      final data = snap.data();
      return snap.exists && data != null ? data['emoji'] as String? : null;
    });
  }

  @override
  Stream<List<Comment>> watchComments(String postId) {
    return _posts
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs.map((d) => Comment.fromMap(domainMap(d))).toList());
  }

  @override
  Future<Comment> addComment({
    required Post post,
    required UserProfileRef author,
    required String text,
    List<String> mentions = const [],
  }) async {
    final doc = _posts.doc(post.postId).collection('comments').doc();
    final comment = Comment(
      commentId: doc.id,
      postId: post.postId,
      authorUid: author.uid,
      authorName: author.displayName,
      authorPhoto: author.photoUrl,
      text: text,
      mentions: mentions,
      createdAt: DateTime.now(),
    );
    await doc.set(withTimestamps(comment.toMap()));
    return comment;
  }

  @override
  Stream<List<UserProfile>> suggestions({int limit = 8}) {
    // People the reader could still follow. Firestore's `whereNotIn` caps at ten
    // values and a followed account list can exceed that, so this scans a bounded
    // page and excludes the followed set in memory — a bounded read beats an
    // unbounded one on metered data.
    final me = FirebaseAuth.instance.currentUser?.uid;
    final followingUids = _firestore.collection('follows').where('followerUid', isEqualTo: me);
    return followingUids.snapshots().asyncMap((edges) async {
      final excluded = <String>{
        if (me != null) me,
        for (final edge in edges.docs)
          if (edge.data()['followingUid'] is String) edge.data()['followingUid']! as String,
      };
      final scan = await _firestore
          .collection('users')
          .orderBy('displayName')
          .limit((limit + excluded.length).clamp(0, 100).toInt())
          .get();
      return scan.docs
          .map(domainMap)
          .map(UserProfile.fromMap)
          .where((u) => !excluded.contains(u.uid))
          .take(limit)
          .toList();
    });
  }

  /// The only posts a `list` query may return without a per-document follower
  /// check — kept identical to the `allow list` clause in `firestore.rules`.
  Query<Map<String, dynamic>> _publicPostsQuery() =>
      _posts.where('audience', isEqualTo: Audience.everyone.name);

  @override
  Future<Post?> loadPost(String postId) async {
    final snap = await _posts.doc(postId).get();
    if (!snap.exists) return null;
    // The rules decide whether this reader may have the document at all, so a
    // followers-only post refused here surfaces as the same permission error the
    // rest of the app already renders.
    return Post.fromMap(domainMap(snap));
  }

  List<Post> _postsFrom(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.map((d) => Post.fromMap(domainMap(d))).toList();
}
