import 'package:equatable/equatable.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/media.dart';

/// A feed item.
///
/// The author's name and photo are embedded rather than referenced: a feed
/// render would otherwise need one user lookup per row, which is the single
/// largest avoidable latency cost in this app. Counters are fields maintained
/// server-side.
class Post extends Equatable {
  const Post({
    required this.postId,
    required this.authorUid,
    required this.authorName,
    this.authorPhoto,
    this.caption = '',
    this.media = const [],
    this.audience = Audience.everyone,
    this.likesCount = 0,
    this.commentsCount = 0,
    required this.createdAt,
    this.myReaction,
  });

  final String postId;
  final String authorUid;
  final String authorName;
  final String? authorPhoto;
  final String caption;
  final List<MediaRef> media;
  final Audience audience;
  final int likesCount;
  final int commentsCount;
  final DateTime createdAt;

  /// Reaction written by the reading user, resolved separately from the
  /// document because it is per-reader state, not shared content.
  final String? myReaction;

  bool get hasMedia => media.any((m) => !m.isEmpty);

  /// Media that is safe to lay out in the list: anything with a thumbnail or a
  /// placeholder, never a full-resolution download.
  List<MediaRef> get layoutMedia => media.where((m) => !m.isEmpty).toList();

  Post copyWith({String? myReaction, int? likesCount, int? commentsCount, List<MediaRef>? media}) {
    return Post(
      postId: postId,
      authorUid: authorUid,
      authorName: authorName,
      authorPhoto: authorPhoto,
      caption: caption,
      media: media ?? this.media,
      audience: audience,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      createdAt: createdAt,
      myReaction: myReaction ?? this.myReaction,
    );
  }

  Map<String, Object?> toMap() => {
    'postId': postId,
    'authorUid': authorUid,
    'authorName': authorName,
    'authorPhoto': authorPhoto,
    'caption': caption,
    'mediaRefs': media.map((m) => m.toMap()).toList(),
    'audience': audience.name,
    'likesCount': likesCount,
    'commentsCount': commentsCount,
    'createdAt': createdAt,
  };

  static Post fromMap(Map<String, Object?> map) {
    return Post(
      postId: map['postId'] as String? ?? '',
      authorUid: map['authorUid'] as String? ?? '',
      authorName: map['authorName'] as String? ?? '',
      authorPhoto: map['authorPhoto'] as String?,
      caption: map['caption'] as String? ?? '',
      media: (map['mediaRefs'] as List? ?? const [])
          .map((e) => MediaRef.fromMap((e as Map).cast<String, dynamic>()))
          .toList(),
      audience: Audience.parse(map['audience'] as String?),
      likesCount: (map['likesCount'] as num?)?.toInt() ?? 0,
      commentsCount: (map['commentsCount'] as num?)?.toInt() ?? 0,
      createdAt: map['createdAt'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  List<Object?> get props => [postId, authorUid, caption, media, audience, likesCount, commentsCount, createdAt, myReaction];
}

/// Discussion lives in `posts/{postId}/comments`, so a post and its thread are
/// read together and deleted together.
class Comment extends Equatable {
  const Comment({
    required this.commentId,
    required this.postId,
    required this.authorUid,
    required this.authorName,
    this.authorPhoto,
    required this.text,
    this.mentions = const [],
    required this.createdAt,
  });

  final String commentId;
  final String postId;
  final String authorUid;
  final String authorName;
  final String? authorPhoto;
  final String text;

  /// Uids mentioned in [text], resolved by the write path so notification
  /// fan-out does not have to re-parse text in a Function.
  final List<String> mentions;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
    'commentId': commentId,
    'postId': postId,
    'authorUid': authorUid,
    'authorName': authorName,
    'authorPhoto': authorPhoto,
    'text': text,
    'mentions': mentions,
    'createdAt': createdAt,
  };

  static Comment fromMap(Map<String, Object?> map) => Comment(
    commentId: map['commentId'] as String? ?? '',
    postId: map['postId'] as String? ?? '',
    authorUid: map['authorUid'] as String? ?? '',
    authorName: map['authorName'] as String? ?? '',
    authorPhoto: map['authorPhoto'] as String?,
    text: map['text'] as String? ?? '',
    mentions: (map['mentions'] as List? ?? const []).cast<String>(),
    createdAt: map['createdAt'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  List<Object?> get props => [commentId, postId, authorUid, text, createdAt];
}

/// A reaction is one document per (post, reader), which keeps the shared
/// counter authoritative while letting the client know its own state.
class Reaction extends Equatable {
  const Reaction({required this.postId, required this.uid, required this.emoji, required this.createdAt});

  final String postId;
  final String uid;
  final String emoji;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {'postId': postId, 'uid': uid, 'emoji': emoji, 'createdAt': createdAt};

  static Reaction fromMap(Map<String, Object?> map) => Reaction(
    postId: map['postId'] as String? ?? '',
    uid: map['uid'] as String? ?? '',
    emoji: map['emoji'] as String? ?? '',
    createdAt: map['createdAt'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  List<Object?> get props => [postId, uid, emoji];
}
