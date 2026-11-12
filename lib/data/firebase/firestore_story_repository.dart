import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:liyu_social/data/firebase/converters.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/media.dart';
import 'package:liyu_social/domain/models/story.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// Stories against `stories`, scoped to the reader and the accounts they follow.
///
/// A story has no audience field — by design it is visible only to its author
/// and the author's followers, and only until `expiresAt`. `watchActive` therefore
/// reads a bounded author set (the reader plus their followees, capped at what a
/// `whereIn` can carry) and filters `expiresAt > now` in the query, then re-checks
/// expiry in memory so a document the nightly cleanup has not reaped yet cannot
/// open. `markViewed` uses an array union so concurrent viewers never clobber
/// each other's entries.
class FirestoreStoryRepository implements StoryRepository {
  FirestoreStoryRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _stories => _firestore.collection('stories');
  CollectionReference<Map<String, dynamic>> get _follows => _firestore.collection('follows');

  @override
  Stream<List<Story>> watchActive({required String uid}) async* {
    final allowed = await _allowedAuthors(uid);
    yield* _stories
        .where('authorUid', whereIn: allowed)
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .snapshots()
        .map((snap) {
          final now = DateTime.now();
          return snap.docs
              .map((d) => Story.fromMap(domainMap(d)))
              .where((s) => !s.isExpiredAt(now))
              .toList();
        });
  }

  @override
  Future<Story> publish({
    required UserProfileRef author,
    required MediaRef media,
    String caption = '',
    Duration ttl = const Duration(hours: 24),
  }) async {
    final doc = _stories.doc();
    final now = DateTime.now();
    final story = Story(
      storyId: doc.id,
      authorUid: author.uid,
      authorName: author.displayName,
      authorPhoto: author.photoUrl,
      media: media,
      caption: caption,
      createdAt: now,
      // Expiry is a stored timestamp, not a client-side countdown: it is what the
      // scheduled cleanup and the security rules both read, so the server and the
      // rules agree on when a story stops being retrievable.
      expiresAt: now.add(ttl),
    );
    await doc.set(withTimestamps(story.toMap()));
    return story;
  }

  @override
  Future<void> markViewed({required String storyId, required String uid}) {
    return _stories.doc(storyId).update({'viewerUids': FieldValue.arrayUnion([uid])});
  }

  /// The reader plus the accounts they follow. `whereIn` accepts at most ten
  /// values, so the set is capped there — beyond that a user follows more than
  /// one live rail can hold, which is a fan-out concern, not a read one.
  Future<List<String>> _allowedAuthors(String uid) async {
    final edges = await _follows.where('followerUid', isEqualTo: uid).get();
    final authors = <String>{
      uid,
      for (final edge in edges.docs)
        if (edge.data()['followingUid'] is String) edge.data()['followingUid']! as String,
    };
    return authors.take(10).toList();
  }
}
