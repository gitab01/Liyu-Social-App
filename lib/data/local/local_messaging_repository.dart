import 'dart:async';

import 'package:liyu_social/core/offline/write_queue.dart';
import 'package:liyu_social/data/local/local_counters.dart';
import 'package:liyu_social/data/local/local_queries.dart';
import 'package:liyu_social/data/local/local_store.dart';
import 'package:liyu_social/data/local/local_watch.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/notification.dart';
import 'package:liyu_social/domain/models/user.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Direct messages: inbox list, live threads, optimistic send and retry.
///
/// The thread is stored under a [Message.messageId] the client minted before
/// the first attempt. A retry after a dropped connection therefore rewrites the
/// same document instead of creating a second copy — which is the entire reason
/// optimistic sending can be honest about delivery.
class LocalMessagingRepository implements MessagingRepository {
  LocalMessagingRepository({
    required LocalStore store,
    required LocalQueries queries,
    required LocalCounters counters,
    required LocalWriteQueue queue,
    required ConnectionMonitor monitor,
    Duration Function()? transferDelay,
  })  : _store = store,
        _queries = queries,
        _counters = counters,
        _queue = queue,
        _monitor = monitor,
        _transferDelay = transferDelay ?? (() => const Duration(milliseconds: 220)) {
    _queue.pendingWrites.addListener(() {
      if (_queue.pendingWrites.value == 0) _drainFailed();
    });
  }

  final LocalStore _store;
  final LocalQueries _queries;
  final LocalCounters _counters;
  final LocalWriteQueue _queue;
  final ConnectionMonitor _monitor;
  final Duration Function() _transferDelay;
  final Set<String> _inFlight = {};

  @override
  Stream<List<Conversation>> watchInbox(String uid) => watchCollections<List<Conversation>>(
    _store,
    const ['conversations', 'messages', 'users'],
    () {
      final list = _store
          .all('conversations')
          .map((doc) => _conversationFor(doc, uid))
          .whereType<Conversation>()
          .toList()
        ..sort((a, b) => (b.lastMessageAt ?? DateTime(1970)).compareTo(a.lastMessageAt ?? DateTime(1970)));
      return list;
    },
  );

  /// The peer is whoever the reader is not talking to, which is a function of
  /// the reader — a single stored `peerUid` would be wrong for one of them.
  Conversation? _conversationFor(Map<String, Object?> doc, String readerUid) {
    final stored = Conversation.fromMap(doc);
    if (!stored.participantUids.contains(readerUid)) return null;
    final peerUid = stored.participantUids.firstWhere((uid) => uid != readerUid);
    final profile = _queries.user(peerUid);
    return Conversation(
      conversationId: stored.conversationId,
      participantUids: stored.participantUids,
      peer: UserProfileRef(
        uid: peerUid,
        displayName: profile?.displayName ?? stored.peer.displayName,
        photoUrl: profile?.photoUrl ?? stored.peer.photoUrl,
      ),
      lastMessage: stored.lastMessage,
      lastMessageAt: stored.lastMessageAt,
      lastSenderUid: stored.lastSenderUid,
      unreadCounts: stored.unreadCounts,
    );
  }

  @override
  Stream<List<Message>> watchThread(String conversationId, {int limit = 50}) => watchCollections<List<Message>>(
    _store,
    const ['messages'],
    () {
      final messages = _store
          .all('messages')
          .where((doc) => doc['conversationId'] == conversationId)
          .map(Message.fromMap)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return messages.length <= limit ? messages : messages.sublist(messages.length - limit);
    },
  );

  @override
  Future<String> openConversationWith({required String myUid, required UserProfileRef peer}) async {
    // Sorting the two uids makes the id a pure function of the pair, so two
    // clients starting the same thread converge on one document.
    final pair = [myUid, peer.uid]..sort();
    final id = '${pair.first}_${pair.last}';
    final existing = _store.doc('conversations', id);
    if (existing != null) return id;

    await _store.put('conversations', id, {
      'conversationId': id,
      'participantUids': pair,
      'peerUid': peer.uid == pair.first ? peer.uid : myUid,
      'peerName': peer.displayName,
      'peerPhoto': peer.photoUrl,
      'lastMessage': '',
      'lastSenderUid': null,
      'unreadCounts': {myUid: 0, peer.uid: 0},
      'createdAt': DateTime.now(),
    });
    return id;
  }

  @override
  Future<Message> send(Message message) async {
    final conversation = _store.doc('conversations', message.conversationId);
    if (conversation == null) throw StateError('conversation not found');

    _inFlight.add(message.messageId);
    // Store as pending first, so the bubble appears in the thread immediately.
    await _store.upsert('messages', message.messageId, message.copyWith(status: MessageStatus.pending).toMap());

    if (!_monitor.online) {
      // Offline: the queue replays the identical write, which lands at the same
      // document id and flips the bubble to sent.
      final queued = await _queue.enqueue(QueueKind.message, 'message ${message.messageId}', () => _deliver(message));
      _inFlight.remove(message.messageId);
      return queued;
    }

    final delivered = await _deliver(message);
    _inFlight.remove(message.messageId);
    return delivered;
  }

  Future<Message> _deliver(Message message) async {
    try {
      await Future<void>.delayed(_transferDelay());
      final sent = message.copyWith(status: MessageStatus.sent, deliveredAt: DateTime.now());
      await _store.upsert('messages', sent.messageId, sent.toMap());
      await _counters.onMessage(sent, incrementUnread: sent.senderUid != sent.recipientUid);
      await _notifyRecipient(sent);
      return sent;
    } on Object catch (error) {
      final failed = message.copyWith(status: MessageStatus.failed, error: error.toString());
      await _store.upsert('messages', failed.messageId, failed.toMap());
      return failed;
    }
  }

  @override
  Future<Message> retry(Message message) => send(message);

  Future<void> _drainFailed() async {
    for (final doc in _store.all('messages')) {
      final message = Message.fromMap(doc);
      if (message.status == MessageStatus.failed && !_inFlight.contains(message.messageId)) {
        await retry(message);
      }
    }
  }

  @override
  Future<void> markRead({required String conversationId, required String uid}) =>
      _counters.clearUnread(conversationId: conversationId, uid: uid);

  @override
  Future<List<UserProfile>> searchPeople(String query, {int limit = 10}) async {
    final needle = query.toLowerCase();
    final viewer = _store.sessionUid;
    final blocked = viewer == null ? const <String>{} : _queries.blockingOf(viewer);
    return _queries
        .allUsers()
        .where((u) => u.uid != viewer && !blocked.contains(u.uid))
        .where((u) => u.displayName.toLowerCase().contains(needle))
        .take(limit)
        .toList();
  }

  Future<void> _notifyRecipient(Message message) async {
    if (message.senderUid == message.recipientUid) return;
    final actor = _queries.user(message.senderUid);
    await _counters.notify(
      notification: AppNotification(
        id: _uuid.v4(),
        recipientUid: message.recipientUid,
        type: NotificationType.message,
        actorName: actor?.displayName ?? 'Someone',
        actorUid: message.senderUid,
        actorPhoto: actor?.photoUrl,
        body: message.text.isEmpty ? 'sent a photo' : message.text,
        conversationId: message.conversationId,
        createdAt: DateTime.now(),
      ),
    );
  }
}
