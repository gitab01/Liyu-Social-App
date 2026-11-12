import 'package:equatable/equatable.dart';

/// A profile document. Social counts are stored fields, not derived reads, and
/// are mutated by Cloud Functions rather than by clients.
class UserProfile extends Equatable {
  const UserProfile({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.bio = '',
    this.phone,
    this.email,
    this.languageCode = 'en',
    this.followersCount = 0,
    this.followingCount = 0,
    this.postsCount = 0,
    this.blocking = const {},
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
  final String bio;
  final String? phone;
  final String? email;

  /// `en` or `am`. Interface copy is Amharic-first; this drives the default
  /// locale for the signed-in reader.
  final String languageCode;

  final int followersCount;
  final int followingCount;
  final int postsCount;

  /// Uids this account blocked. Kept on the profile so a reader can filter a
  /// feed in one pass without a collection group query.
  final Set<String> blocking;

  bool get hasBlocks => blocking.isNotEmpty;

  UserProfile copyWith({
    String? displayName,
    String? photoUrl,
    String? bio,
    String? phone,
    String? email,
    String? languageCode,
    int? followersCount,
    int? followingCount,
    int? postsCount,
    Set<String>? blocking,
  }) {
    return UserProfile(
      uid: uid,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      bio: bio ?? this.bio,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      languageCode: languageCode ?? this.languageCode,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      postsCount: postsCount ?? this.postsCount,
      blocking: blocking ?? this.blocking,
    );
  }

  Map<String, Object?> toMap() => {
    'uid': uid,
    'displayName': displayName,
    'photoUrl': photoUrl,
    'bio': bio,
    'phone': phone,
    'email': email,
    'languageCode': languageCode,
    'followersCount': followersCount,
    'followingCount': followingCount,
    'postsCount': postsCount,
    'blocking': blocking.toList(),
  };

  static UserProfile fromMap(Map<String, Object?> map) {
    return UserProfile(
      uid: map['uid'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      photoUrl: map['photoUrl'] as String?,
      bio: map['bio'] as String? ?? '',
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      languageCode: map['languageCode'] as String? ?? 'en',
      followersCount: (map['followersCount'] as num?)?.toInt() ?? 0,
      followingCount: (map['followingCount'] as num?)?.toInt() ?? 0,
      postsCount: (map['postsCount'] as num?)?.toInt() ?? 0,
      blocking: (map['blocking'] as List?)?.cast<String>().toSet() ?? const {},
    );
  }

  @override
  List<Object?> get props => [uid, displayName, photoUrl, bio, languageCode, followersCount, followingCount, postsCount, blocking];
}

/// An edge in the social graph. Stored once per direction so both "who I
/// follow" and "who follows me" resolve from a compound index.
class FollowEdge extends Equatable {
  const FollowEdge({required this.followerUid, required this.followingUid, required this.createdAt});

  final String followerUid;
  final String followingUid;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
    'followerUid': followerUid,
    'followingUid': followingUid,
    'createdAt': createdAt,
  };

  static FollowEdge fromMap(Map<String, Object?> map) => FollowEdge(
    followerUid: map['followerUid'] as String? ?? '',
    followingUid: map['followingUid'] as String? ?? '',
    createdAt: map['createdAt'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  List<Object?> get props => [followerUid, followingUid, createdAt];
}
