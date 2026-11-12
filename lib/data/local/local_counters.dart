import 'package:liyu_social/data/local/local_store.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/notification.dart';
import 'package:liyu_social/domain/models/post.dart';
import 'package:liyu_social/domain/models/user.dart';

/// Counter maintenance for the local backend.
///
/// In the Firebase build these fields belong to Cloud Functions, not clients —
/// that is what stops a modified client from inflating its own follower
/// numbers. The local backend has no Functions, so the same rule is enforced by
/// keeping every count mutation behind this class: repositories never assign a
/// count directly.
class LocalCounters {
  LocalCounters(this._store);

  final LocalStore _store;

  Future<void> onPostAdded(String authorUid) => _bumpUser(authorUid, 'postsCount', 1);

  Future<void> onPostDeleted(Post post) async {
    await _bumpUser(post.authorUid, 'postsCount', -1);
  }

  Future<void> onReaction(String postId, int delta) => _bumpPost(postId, 'likesCount', delta);

  Future<void> onComment(String postId, int delta) => _bumpPost(postId, 'commentsCount', delta);

  Future<void> onFollow({required String followerUid, required String followingUid}) async {
    await _bumpUser(followingUid, 'followersCount', 1);
    await _bumpUser(followerUid, 'followingCount', 1);
  }

  Future<void> onUnfollow({required String followerUid, required String followingUid}) async {
    await _bumpUser(followingUid, 'followersCount', -1);
    await _bumpUser(followerUid, 'followingCount', -1);
  }

  /// The inbox renders from these denormalized fields, so a new message has to
  /// update the header in the same write that stores it.
  Future<void> onMessage(Message message, {required bool incrementUnread}) async {
    final conversation = _store.doc('conversations', message.conversationId);
    if (conversation == null) return;

    final preview = message.text.isNotEmpty
        ? message.text
        : (message.hasMedia ? 'Photo' : '');
    final unread = Map<String, int>.from((conversation['unreadCounts'] as Map? ?? {})
        .map((key, value) => MapEntry(key.toString(), (value as num).toInt())));
    if (incrementUnread) {
      unread[message.recipientUid] = (unread[message.recipientUid] ?? 0) + 1;
    }

    await _store.update('conversations', message.conversationId, {
      'lastMessage': preview,
      'lastMessageAt': message.createdAt,
      'lastSenderUid': message.senderUid,
      'unreadCounts': unread,
    });
  }

  Future<void> clearUnread({required String conversationId, required String uid}) async {
    final conversation = _store.doc('conversations', conversationId);
    if (conversation == null) return;
    final unread = Map<String, int>.from((conversation['unreadCounts'] as Map? ?? {})
        .map((key, value) => MapEntry(key.toString(), (value as num).toInt())));
    unread[uid] = 0;
    await _store.update('conversations', conversationId, {'unreadCounts': unread});
  }

  Future<void> notify({
    required AppNotification notification,
  }) => _store.put('notifications', notification.id, notification.toMap());

  Future<void> _bumpPost(String postId, String field, int delta) async {
    final doc = _store.doc('posts', postId);
    if (doc == null) return;
    final current = (doc[field] as num?)?.toInt() ?? 0;
    await _store.update('posts', postId, {field: (current + delta).clamp(0, 1 << 31)});
  }

  Future<void> _bumpUser(String uid, String field, int delta) async {
    final doc = _store.doc('users', uid);
    if (doc == null) return;
    final current = (doc[field] as num?)?.toInt() ?? 0;
    await _store.update('users', uid, {field: (current + delta).clamp(0, 1 << 31)});
  }

  UserProfile? user(String uid) {
    final doc = _store.doc('users', uid);
    return doc == null ? null : UserProfile.fromMap(doc);
  }

  Conversation? conversation(String id) {
    final doc = _store.doc('conversations', id);
    return doc == null ? null : Conversation.fromMap(doc);
  }
}
