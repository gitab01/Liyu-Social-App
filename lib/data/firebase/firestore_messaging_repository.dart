import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:liyu_social/data/firebase/converters.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/user.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// Real-time DMs against `conversations` and `conversations/{id}/messages`.
///
/// Everything here exists to survive a dropped connection. The conversation id
/// is derived by sorting the two uids and joining them, so the same pair of
/// people can only ever resolve to one thread and a duplicate is structurally
/// impossible. A message is written at the *client-generated* messageId path
/// with `SetOptions(merge: true)` — Firestore offline persistence replays that
/// write when the socket returns, and because it lands on the same document a
/// retry cannot mint a second copy. The unread badge lives on the conversation
/// header and is only ever touched inside a transaction, so two simultaneous
/// sends from the same peer cannot lose an increment.
class FirestoreMessagingRepository implements MessagingRepository {
  FirestoreMessagingRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Messages whose write never reached the server (a hard failure, not a queued
  /// one). They live only in memory and are merged into the thread so a failed
  /// bubble and its retry control can be shown.
  final Map<String, Message> _outbox = {};
  final StreamController<void> _outboxChanged = StreamController<void>.broadcast();

  CollectionReference<Map<String, dynamic>> get _conversations => _firestore.collection('conversations');

  @override
  Stream<List<Conversation>> watchInbox(String uid) {
    return _conversations
        .where('participantUids', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Conversation.fromMap(domainMap(d))).toList());
  }

  @override
  Stream<List<Message>> watchThread(String conversationId, {int limit = 50}) {
    final query = _conversations
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit);

    final controller = StreamController<List<Message>>();
    List<Message> remote = const [];

    // `hasPendingWrites` is Firestore telling us the document is still in the
    // local queue, which is exactly the optimistic "sending" state — no separate
    // pending mechanism is needed while the write is merely deferred.
    void emit() {
      if (controller.isClosed) return;
      final remoteIds = remote.map((m) => m.messageId).toSet();
      final pending = _outbox.values
          .where((m) => m.conversationId == conversationId && !remoteIds.contains(m.messageId))
          .toList();
      final merged = [...remote, ...pending]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      controller.add(merged);
    }

    final remoteSub = query.snapshots().listen(
      (snap) {
        remote = snap.docs.map(_messageFrom).toList();
        emit();
      },
      onError: (Object error, StackTrace stack) => controller.addError(error, stack),
    );
    final outboxSub = _outboxChanged.stream.listen((_) => emit());

    controller.onCancel = () {
      remoteSub.cancel();
      outboxSub.cancel();
    };
    return controller.stream;
  }

  @override
  Future<String> openConversationWith({required String myUid, required UserProfileRef peer}) async {
    final id = conversationIdFor(myUid, peer.uid);
    final ref = _conversations.doc(id);
    // Existing threads are left untouched — reopening a chat must not clobber the
    // last-message preview or the unread counts.
    if ((await ref.get()).exists) return id;

    final conversation = Conversation(
      conversationId: id,
      participantUids: [myUid, peer.uid]..sort(),
      peer: peer,
      lastMessageAt: DateTime.now(),
      unreadCounts: {myUid: 0, peer.uid: 0},
    );
    await ref.set(withTimestamps(conversation.toMap()));
    return id;
  }

  @override
  Future<Message> send(Message message) async {
    final ref = _conversations.doc(message.conversationId).collection('messages').doc(message.messageId);
    // Show it immediately; if the socket is down Firestore still writes to the
    // local cache and the thread listener republishes it as `pending`.
    _outbox[message.messageId] = message.copyWith(status: MessageStatus.pending);
    _outboxChanged.add(null);
    try {
      await ref.set(
        withTimestamps(message.copyWith(status: MessageStatus.sent).toMap()),
        SetOptions(merge: true),
      );
      await _bumpConversation(message);
      _outbox.remove(message.messageId);
      _outboxChanged.add(null);
      return message.copyWith(status: MessageStatus.sent);
    } on Object catch (error) {
      _outbox[message.messageId] = message.copyWith(status: MessageStatus.failed, error: '$error');
      _outboxChanged.add(null);
      rethrow;
    }
  }

  @override
  Future<Message> retry(Message message) => send(message);

  @override
  Future<void> markRead({required String conversationId, required String uid}) {
    final ref = _conversations.doc(conversationId);
    // Read-modify-write in a transaction so only the reader's own unread entry
    // is zeroed; the sender's entry and every other field stay intact.
    return _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final unread = _readUnread(snap.get('unreadCounts'));
      unread[uid] = 0;
      tx.update(ref, {'unreadCounts': unread});
    });
  }

  @override
  Future<List<UserProfile>> searchPeople(String query, {int limit = 10}) async {
    final needle = query.trim();
    if (needle.isEmpty) return const [];
    // A `displayName` prefix range is the cheap way to search without a full
    // scan; the trailing U+F8FF is Firestore's last sort code point, so the range
    // captures exactly the names beginning with the query. The in-memory filter
    // then tolerates the case differences Firestore's range is blind to.
    final snap = await _firestore
        .collection('users')
        .orderBy('displayName')
        .where('displayName', isGreaterThanOrEqualTo: needle, isLessThanOrEqualTo: '$needle\uf8ff')
        .limit(limit * 2)
        .get();
    final lower = needle.toLowerCase();
    return snap.docs
        .map(domainMap)
        .map(UserProfile.fromMap)
        .where((u) => u.displayName.toLowerCase().contains(lower))
        .take(limit)
        .toList();
  }

  /// The deterministic thread id. Sorting first means (a, b) and (b, a) map to
  /// the same key, which is the entire reason a duplicate conversation cannot be
  /// created by the two clients opening the chat at the same moment.
  static String conversationIdFor(String a, String b) {
    final pair = [a, b]..sort();
    return pair.join('_');
  }

  Message _messageFrom(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final message = Message.fromMap(domainMap(doc));
    if (doc.metadata.hasPendingWrites) return message.copyWith(status: MessageStatus.pending);
    return message;
  }

  Future<void> _bumpConversation(Message message) {
    final ref = _conversations.doc(message.conversationId);
    return _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final unread = _readUnread(snap.exists ? snap.get('unreadCounts') : null);
      unread[message.recipientUid] = (unread[message.recipientUid] ?? 0) + 1;
      unread.putIfAbsent(message.senderUid, () => 0);
      // `merge: true` keeps the peer snapshot written at open time; only the
      // preview and the unread map move here.
      tx.set(
        ref,
        withTimestamps({
          'lastMessage': message.text,
          'lastMessageAt': message.createdAt,
          'lastSenderUid': message.senderUid,
          'unreadCounts': unread,
        }),
        SetOptions(merge: true),
      );
    });
  }

  Map<String, int> _readUnread(Object? raw) {
    if (raw is! Map) return {};
    return raw.map((key, value) => MapEntry(key as String, (value as num).toInt()));
  }

  /// Releases the broadcast controller for tests and teardown. Firestore itself
  /// needs no close.
  void dispose() => _outboxChanged.close();
}
