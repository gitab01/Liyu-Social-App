import 'package:liyu_social/data/local/local_counters.dart';
import 'package:liyu_social/data/local/local_queries.dart';
import 'package:liyu_social/data/local/local_store.dart';
import 'package:liyu_social/data/local/local_watch.dart';
import 'package:liyu_social/domain/access_rules.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/notification.dart';
import 'package:liyu_social/domain/models/user.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';
import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// The social graph: profiles, follow edges, blocks.
///
/// Follow counts are not written here — they move through [LocalCounters], the
/// local stand-in for the counter functions, so that no client-side path can
/// inflate a number the UI then displays.
class LocalProfileRepository implements ProfileRepository {
  LocalProfileRepository({
    required LocalStore store,
    required LocalQueries queries,
    required LocalCounters counters,
  })  : _store = store,
        _queries = queries,
        _counters = counters;

  final LocalStore _store;
  final LocalQueries _queries;
  final LocalCounters _counters;

  @override
  Future<UserProfile?> load(String uid) async => _queries.user(uid);

  @override
  Stream<UserProfile?> watch(String uid) =>
      watchCollections<UserProfile?>(_store, const ['users'], () => _queries.user(uid));

  @override
  Stream<bool> watchFollowing({required String followerUid, required String targetUid}) => watchCollections<bool>(
    _store,
    const ['follows'],
    () => _queries.follows(followerUid: followerUid, followingUid: targetUid),
  );

  @override
  Future<void> setFollow({required String followerUid, required String targetUid, required bool following}) async {
    if (followerUid == targetUid) throw StateError('cannot follow yourself');
    final edge = FollowEdge(followerUid: followerUid, followingUid: targetUid, createdAt: DateTime.now());
    if (!AccessRules.canWriteFollowEdge(edge: edge, uid: followerUid)) {
      throw StateError('permission-denied: you may only write your own edges');
    }

    // The edge id is the pair, so a double tap cannot create two edges and
    // double-count a follower.
    final id = '${followerUid}_$targetUid';
    final exists = _store.doc('follows', id) != null;
    if (following) {
      if (exists) return;
      await _store.put('follows', id, edge.toMap());
      await _counters.onFollow(followerUid: followerUid, followingUid: targetUid);
      final actor = _queries.user(followerUid);
      await _counters.notify(
        notification: AppNotification(
          id: _uuid.v4(),
          recipientUid: targetUid,
          type: NotificationType.follow,
          actorName: actor?.displayName ?? 'Someone',
          actorUid: followerUid,
          actorPhoto: actor?.photoUrl,
          body: 'started following you',
          createdAt: DateTime.now(),
        ),
      );
    } else {
      if (!exists) return;
      await _store.delete('follows', id);
      await _counters.onUnfollow(followerUid: followerUid, followingUid: targetUid);
    }
  }

  @override
  Future<void> setBlock({required String blockerUid, required String blockedUid, required bool blocked}) async {
    final blocker = _queries.user(blockerUid);
    if (blocker == null) return;
    final next = {...blocker.blocking};
    if (blocked) {
      next.add(blockedUid);
      // A block removes the graph edges in both directions, so the follow
      // counts stay true to what the rules will let either side read.
      for (final pair in ['${blockerUid}_$blockedUid', '${blockedUid}_$blockerUid']) {
        if (_store.doc('follows', pair) != null) {
          await _store.delete('follows', pair);
          await _counters.onUnfollow(followerUid: blockerUid, followingUid: blockedUid);
        }
      }
    } else {
      next.remove(blockedUid);
    }
    await _store.update('users', blockerUid, {'blocking': next.toList()});
  }

  @override
  Stream<List<UserProfile>> watchConnections({required String uid, required ConnectionKind kind}) =>
      watchCollections<List<UserProfile>>(_store, const ['follows', 'users'], () {
        final uids = kind == ConnectionKind.followers ? _queries.followersOf(uid) : _queries.followingOf(uid);
        return uids.map(_queries.user).whereType<UserProfile>().toList();
      });
}
