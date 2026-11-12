import 'package:flutter_test/flutter_test.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/notification.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

import 'helpers/test_backend.dart';

/// The promises the chat UI makes — "Sending", "Saved offline — will publish
/// when you reconnect", "Retry" — only hold if a send is keyed on an id the
/// client minted before the first attempt. These run against the real local
/// backend, because the idempotency lives in its writes.
void main() {
  late TestBackend backend;
  late MessagingRepository messaging;
  late String uid;
  late String conversationId;

  const peer = UserProfileRef(uid: 'u_hiwot', displayName: 'Hiwot Alemu');

  setUp(() async {
    backend = await TestBackend.open();
    uid = await backend.signInAsDemo();
    messaging = backend.repository(messagingRepositoryProvider);
    conversationId = await messaging.openConversationWith(myUid: uid, peer: peer);
  });

  tearDown(() => backend.dispose());

  Message draft(String id, {String text = 'sent twice?'}) => Message(
    messageId: id,
    conversationId: conversationId,
    senderUid: uid,
    recipientUid: peer.uid,
    text: text,
    status: MessageStatus.pending,
    createdAt: DateTime.now(),
  );

  List<Message> stored(String id) => backend.store
      .all('messages')
      .map(Message.fromMap)
      .where((m) => m.messageId == id)
      .toList();

  test('the session the UI reads is the account that signed in', () async {
    // The session is a stream, so its first value arrives a tick after sign-in
    // resolves — reading the derived provider synchronously would still be
    // loading. Awaiting the future is what the widget tree effectively does.
    final session = await backend.container.read(signedInUserProvider.future);
    expect(session?.uid, uid);
    expect(backend.container.read(currentUidProvider), uid);
  });

  test('both sides of a thread resolve the same conversation id', () async {
    final fromPeer = await messaging.openConversationWith(
      myUid: peer.uid,
      peer: UserProfileRef(uid: uid, displayName: 'Selam Bekele'),
    );
    expect(fromPeer, conversationId);
    expect(backend.store.all('conversations').where((d) => Conversation.fromMap(d).conversationId == conversationId).length, 1);
  });

  test('an online send lands as sent and writes one document', () async {
    final sent = await messaging.send(draft('m_online'));

    expect(sent.status, MessageStatus.sent);
    expect(sent.deliveredAt, isNotNull);
    expect(stored('m_online'), hasLength(1));
  });

  test('a send written while offline is delivered on reconnect, exactly once', () async {
    final message = draft('m_offline');
    backend.monitor.setNetworkAvailable(false);

    final delivered = messaging.send(message);
    await Future<void>.delayed(Duration.zero);

    expect(stored('m_offline').single.status, MessageStatus.pending);
    expect(backend.queue.pendingWrites.value, 1);

    backend.monitor.setNetworkAvailable(true);
    final result = await delivered;

    expect(result.status, MessageStatus.sent);
    expect(stored('m_offline'), hasLength(1));
    expect(backend.queue.pendingWrites.value, 0);
  });

  test('a retry after a drop rewrites the same document instead of duplicating', () async {
    final failed = draft('m_retry').copyWith(status: MessageStatus.failed, error: 'socket closed');
    await backend.store.upsert('messages', failed.messageId, failed.toMap());
    expect(stored('m_retry').single.status, MessageStatus.failed);

    final retried = await messaging.retry(failed);

    expect(retried.status, MessageStatus.sent);
    expect(stored('m_retry'), hasLength(1));
  });

  test('delivery moves the inbox header and the recipient unread count', () async {
    await messaging.send(draft('m_header', text: 'the thumbnail sizes are final'));

    final conversation = backend.store.doc('conversations', conversationId)!;
    expect(conversation['lastMessage'], 'the thumbnail sizes are final');
    expect(conversation['lastSenderUid'], uid);
    expect((conversation['unreadCounts'] as Map)[peer.uid], 1);
  });

  test('opening the thread clears only the reader own unread count', () async {
    await messaging.send(draft('m_clear'));
    await messaging.markRead(conversationId: conversationId, uid: uid);

    final unread = (backend.store.doc('conversations', conversationId)!['unreadCounts'] as Map);
    expect(unread[uid], 0);
    expect(unread[peer.uid], 1);
  });

  test('the recipient gets the same fan-out document a push would carry', () async {
    await messaging.send(draft('m_fanout', text: 'look at this'));

    final notifications = backend.store
        .all('notifications')
        .map(AppNotification.fromMap)
        .where((n) => n.recipientUid == peer.uid)
        .toList();

    expect(notifications, hasLength(1));
    expect(notifications.single.body, 'look at this');
  });
}
