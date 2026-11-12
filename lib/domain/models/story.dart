import 'package:equatable/equatable.dart';
import 'package:liyu_social/domain/models/media.dart';

/// Ephemeral media. Expiry is a stored timestamp, and a scheduled backend task
/// deletes both the document and the referenced storage object — hiding an
/// expired story is not the same as expiring it.
class Story extends Equatable {
  const Story({
    required this.storyId,
    required this.authorUid,
    required this.authorName,
    this.authorPhoto,
    required this.media,
    this.caption = '',
    required this.createdAt,
    required this.expiresAt,
    this.viewerUids = const {},
  });

  final String storyId;
  final String authorUid;
  final String authorName;
  final String? authorPhoto;
  final MediaRef media;
  final String caption;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// Readers who have already seen it, which is what the unseen indicator on
  /// the rail is computed from.
  final Set<String> viewerUids;

  bool isSeenBy(String uid) => viewerUids.contains(uid);

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);

  Duration remainingAt(DateTime now) {
    final left = expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  Story copyWith({Set<String>? viewerUids, MediaRef? media}) => Story(
    storyId: storyId,
    authorUid: authorUid,
    authorName: authorName,
    authorPhoto: authorPhoto,
    media: media ?? this.media,
    caption: caption,
    createdAt: createdAt,
    expiresAt: expiresAt,
    viewerUids: viewerUids ?? this.viewerUids,
  );

  Map<String, Object?> toMap() => {
    'storyId': storyId,
    'authorUid': authorUid,
    'authorName': authorName,
    'authorPhoto': authorPhoto,
    'mediaRef': media.toMap(),
    'caption': caption,
    'createdAt': createdAt,
    'expiresAt': expiresAt,
    'viewerUids': viewerUids.toList(),
  };

  static Story fromMap(Map<String, Object?> map) => Story(
    storyId: map['storyId'] as String? ?? '',
    authorUid: map['authorUid'] as String? ?? '',
    authorName: map['authorName'] as String? ?? '',
    authorPhoto: map['authorPhoto'] as String?,
    media: MediaRef.fromMap((map['mediaRef'] as Map?)?.cast<String, dynamic>()),
    caption: map['caption'] as String? ?? '',
    createdAt: map['createdAt'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0),
    expiresAt: map['expiresAt'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0),
    viewerUids: (map['viewerUids'] as List? ?? const []).cast<String>().toSet(),
  );

  @override
  List<Object?> get props => [storyId, authorUid, media, caption, expiresAt, viewerUids];
}

/// Stories grouped per author, which is how the rail renders: one avatar circle
/// per person, and the viewer walks that group's items in order.
class StoryGroup extends Equatable {
  const StoryGroup({required this.authorUid, required this.authorName, required this.stories});

  final String authorUid;
  final String authorName;
  final List<Story> stories;

  bool unseenBy(String uid) => stories.any((s) => !s.isSeenBy(uid));

  DateTime get latestAt => stories.map((s) => s.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);

  @override
  List<Object?> get props => [authorUid, stories];
}
