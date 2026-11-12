import 'package:equatable/equatable.dart';
import 'package:liyu_social/domain/models/enums.dart';

/// An entry in the notification tray. Push delivery (FCM) and this list share
/// the same document: a Function fans one out per event, the tray reads the
/// newest pages, and a tap deep-links from [target] into the thread or post.
class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.recipientUid,
    required this.type,
    required this.actorName,
    this.actorUid,
    this.actorPhoto,
    this.body = '',
    this.postId,
    this.commentId,
    this.conversationId,
    this.storyId,
    this.readAt,
    required this.createdAt,
  });

  final String id;
  final String recipientUid;
  final NotificationType type;
  final String actorName;
  final String? actorUid;
  final String? actorPhoto;
  final String body;

  /// Deep-link targets; exactly one is set per type.
  final String? postId;
  final String? commentId;
  final String? conversationId;
  final String? storyId;

  final DateTime? readAt;
  final DateTime createdAt;

  bool get isUnread => readAt == null;

  int get unreadBadge => isUnread ? 1 : 0;

  /// Route the tray opens when this notification is tapped.
  String get deepLink {
    if (conversationId != null) return '/chat/$conversationId';
    if (postId != null) return '/feed/post/$postId';
    if (actorUid != null && type == NotificationType.follow) return '/profile/$actorUid';
    return '/notifications';
  }

  AppNotification copyWith({DateTime? readAt}) => AppNotification(
    id: id,
    recipientUid: recipientUid,
    type: type,
    actorName: actorName,
    actorUid: actorUid,
    actorPhoto: actorPhoto,
    body: body,
    postId: postId,
    commentId: commentId,
    conversationId: conversationId,
    storyId: storyId,
    readAt: readAt ?? this.readAt,
    createdAt: createdAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'recipientUid': recipientUid,
    'type': type.name,
    'actorName': actorName,
    'actorUid': actorUid,
    'actorPhoto': actorPhoto,
    'body': body,
    'postId': postId,
    'commentId': commentId,
    'conversationId': conversationId,
    'storyId': storyId,
    'readAt': readAt,
    'createdAt': createdAt,
  };

  static AppNotification fromMap(Map<String, Object?> map) => AppNotification(
    id: map['id'] as String? ?? '',
    recipientUid: map['recipientUid'] as String? ?? '',
    type: NotificationType.parse(map['type'] as String?),
    actorName: map['actorName'] as String? ?? '',
    actorUid: map['actorUid'] as String?,
    actorPhoto: map['actorPhoto'] as String?,
    body: map['body'] as String? ?? '',
    postId: map['postId'] as String?,
    commentId: map['commentId'] as String?,
    conversationId: map['conversationId'] as String?,
    storyId: map['storyId'] as String?,
    readAt: map['readAt'] as DateTime?,
    createdAt: map['createdAt'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  List<Object?> get props => [id, recipientUid, type, actorName, body, postId, conversationId, readAt, createdAt];
}
