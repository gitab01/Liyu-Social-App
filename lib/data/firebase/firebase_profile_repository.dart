import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:liyu_social/data/firebase/converters.dart';
import 'package:liyu_social/domain/models/user.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// Profiles and the social graph against `users` and `follows`.
///
/// A follow is one edge document keyed `${follower}_${following}`, so creating
/// an edge is idempotent and both directions of the relationship ("who I
/// follow", "who follows me") resolve from the same collection by which field is
/// queried. The follower/following counts are *not* touched here — the client
/// writes only the edge and a Cloud Function moves the counts; the rules refuse
/// a client that tries to change them directly. Blocking lives on the profile's
/// own `blocking` array, mutated with array union/remove so one account can only
/// ever edit its own block list.
class FirebaseProfileRepository implements ProfileRepository {
  FirebaseProfileRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// How many profiles one connection list resolves. Beyond this the reader has
  /// to page, because fetching every follower of a large account would be the
  /// most expensive screen in the app.
  static const int maxConnectionsResolved = 50;

  CollectionReference<Map<String, dynamic>> get _users => _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _follows => _firestore.collection('follows');

  @override
  Future<UserProfile?> load(String uid) async {
    final snap = await _users.doc(uid).get();
    return snap.exists ? UserProfile.fromMap(domainMap(snap)) : null;
  }

  @override
  Stream<UserProfile?> watch(String uid) {
    return _users.doc(uid).snapshots().map((snap) => snap.exists ? UserProfile.fromMap(domainMap(snap)) : null);
  }

  @override
  Stream<bool> watchFollowing({required String followerUid, required String targetUid}) {
    return _follows.doc(_edgeId(followerUid, targetUid)).snapshots().map((snap) => snap.exists);
  }

  @override
  Future<void> setFollow({required String followerUid, required String targetUid, required bool following}) {
    // A batch keeps the edge creation atomic; when the follow notification and
    // the counter updates move server-side they belong in the same commit, and
    // this is the seam that makes that a one-line change rather than a rewrite.
    final edge = _follows.doc(_edgeId(followerUid, targetUid));
    final batch = _firestore.batch();
    if (following) {
      final followEdge = FollowEdge(followerUid: followerUid, followingUid: targetUid, createdAt: DateTime.now());
      batch.set(edge, withTimestamps(followEdge.toMap()));
    } else {
      batch.delete(edge);
    }
    return batch.commit();
  }

  @override
  Future<void> setBlock({required String blockerUid, required String blockedUid, required bool blocked}) {
    return _users.doc(blockerUid).update({
      'blocking': blocked ? FieldValue.arrayUnion([blockedUid]) : FieldValue.arrayRemove([blockedUid]),
    });
  }

  @override
  Stream<List<UserProfile>> watchConnections({required String uid, required ConnectionKind kind}) {
    // `followers` means "edges whose target is me", `following` means "edges
    // whose source is me". One field picks the direction, the other names the
    // person to resolve.
    final scopedField = kind == ConnectionKind.followers ? 'followingUid' : 'followerUid';
    final personField = kind == ConnectionKind.followers ? 'followerUid' : 'followingUid';

    return _follows.where(scopedField, isEqualTo: uid).snapshots().asyncMap((snap) async {
      // FlutterFire exposes no batched document read, so each profile is fetched
      // in parallel. The page is capped because a list of names is worthless if
      // it costs one unbilled-looking read per follower on a large account.
      final refs = <DocumentReference<Map<String, dynamic>>>[
        for (final edge in snap.docs.take(maxConnectionsResolved))
          if (edge.data()[personField] is String) _users.doc(edge.data()[personField]! as String),
      ];
      if (refs.isEmpty) return <UserProfile>[];
      final docs = await Future.wait(refs.map((ref) => ref.get()));
      return docs
          .where((d) => d.exists)
          .map((d) => UserProfile.fromMap(domainMap(d)))
          .toList();
    });
  }

  String _edgeId(String followerUid, String followingUid) => '${followerUid}_$followingUid';
}
