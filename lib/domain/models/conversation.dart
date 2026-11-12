import 'package:equatable/equatable.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/media.dart';

/// A direct-message thread header.
///
/// `lastMessage` is denormalized from the newest message so the inbox renders
/// from a single query without touching any subcollection.
class Conversation extends Equatable {
  const Conversation({
    required this.conversationId,
    required this.participantUids,
    required this.peer,
    this.lastMessage = '',
    this.lastMessageAt,
    this.lastSenderUid,
    this.unreadCounts = const {},
  });

  final String conversationId;
  final List<String> participantUids;

  /// The other person, resolved at read time so the inbox can render name and
  /// avatar without a second query per row.
  final UserProfileRef peer;

  final String lastMessage;
  final DateTime? lastMessageAt;
  final String? lastSenderUid;
  final Map<String, int> unreadCounts;

  int unreadFor(String uid) => unreadCounts[uid] ?? 0;

  bool get peerSentLast => lastSenderUid != null && lastSenderUid != peer.uid;

  Conversation copyWith({String? lastMessage, DateTime? lastMessageAt, String? lastSenderUid, Map<String, int>? unreadCounts}) {
    return Conversation(
      conversationId: conversationId,
      participantUids: participantUids,
      peer: peer,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastSenderUid: lastSenderUid ?? this.lastSenderUid,
      unreadCounts: unreadCounts ?? this.unreadCounts,
    );
  }

  Map<String, Object?> toMap() => {
    'conversationId': conversationId,
    'participantUids': participantUids,
    'peerUid': peer.uid,
    'peerName': peer.displayName,
    'peerPhoto': peer.photoUrl,
    'lastMessage': lastMessage,
    'lastMessageAt': lastMessageAt,
    'lastSenderUid': lastSenderUid,
    'unreadCounts': unreadCounts,
  };

  static Conversation fromMap(Map<String, Object?> map) {
    final unread = (map['unreadCounts'] as Map? ?? const {}).map(
      (k, v) => MapEntry(k as String, (v as num).toInt()),
    );
    return Conversation(
      conversationId: map['conversationId'] as String? ?? '',
      participantUids: (map['participantUids'] as List? ?? const []).cast<String>(),
      peer: UserProfileRef(
        uid: map['peerUid'] as String? ?? '',
        displayName: map['peerName'] as String? ?? '',
        photoUrl: map['peerPhoto'] as String?,
      ),
      lastMessage: map['lastMessage'] as String? ?? '',
      lastMessageAt: map['lastMessageAt'] as DateTime?,
      lastSenderUid: map['lastSenderUid'] as String?,
      unreadCounts: unread,
    );
  }

  @override
  List<Object?> get props => [conversationId, participantUids, lastMessage, lastMessageAt, unreadCounts];
}

/// Minimal embedded profile, used where only name and avatar are needed.
class UserProfileRef extends Equatable {
  const UserProfileRef({required this.uid, required this.displayName, this.photoUrl});

  final String uid;
  final String displayName;
  final String? photoUrl;

  @override
  List<Object?> get props => [uid, displayName, photoUrl];
}

/// A single message.
///
/// [messageId] is generated on the client before the first attempt, so a retry
/// after a dropped connection writes the same document twice rather than
/// creating a duplicate. That idempotency is what makes optimistic sending
/// safe.
class Message extends Equatable {
  const Message({
    required this.messageId,
    required this.conversationId,
    required this.senderUid,
    required this.recipientUid,
    this.text = '',
    this.media,
    this.status = MessageStatus.sent,
    this.error,
    required this.createdAt,
    this.deliveredAt,
  });

  final String messageId;
  final String conversationId;
  final String senderUid;
  final String recipientUid;
  final String text;
  final MediaRef? media;
  final MessageStatus status;

  /// Human-readable reason for a failure, surfaced next to the retry control.
  final String? error;
  final DateTime createdAt;
  final DateTime? deliveredAt;

  bool get hasMedia => media != null && !media!.isEmpty;

  Message copyWith({MessageStatus? status, String? error, DateTime? deliveredAt, MediaRef? media}) {
    return Message(
      messageId: messageId,
      conversationId: conversationId,
      senderUid: senderUid,
      recipientUid: recipientUid,
      text: text,
      media: media ?? this.media,
      status: status ?? this.status,
      error: error ?? this.error,
      createdAt: createdAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
    );
  }

  Map<String, Object?> toMap() => {
    'messageId': messageId,
    'conversationId': conversationId,
    'senderUid': senderUid,
    'recipientUid': recipientUid,
    'text': text,
    'mediaRef': media?.toMap(),
    'status': status.name,
    'error': error,
    'createdAt': createdAt,
    'deliveredAt': deliveredAt,
  };

  static Message fromMap(Map<String, Object?> map) => Message(
    messageId: map['messageId'] as String? ?? '',
    conversationId: map['conversationId'] as String? ?? '',
    senderUid: map['senderUid'] as String? ?? '',
    recipientUid: map['recipientUid'] as String? ?? '',
    text: map['text'] as String? ?? '',
    media: map['mediaRef'] == null ? null : MediaRef.fromMap((map['mediaRef'] as Map).cast<String, dynamic>()),
    status: MessageStatus.parse(map['status'] as String?),
    error: map['error'] as String?,
    createdAt: map['createdAt'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0),
    deliveredAt: map['deliveredAt'] as DateTime?,
  );

  @override
  List<Object?> get props => [messageId, conversationId, senderUid, text, media, status, deliveredAt];
}
