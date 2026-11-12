import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/media.dart';
import 'package:liyu_social/domain/models/notification.dart';
import 'package:liyu_social/domain/models/post.dart';
import 'package:liyu_social/domain/models/story.dart';
import 'package:liyu_social/domain/models/user.dart';

/// Deterministic demo content for the local backend.
///
/// Media references are seeded with null urls and realistic byte counts, so the
/// feed exercises the placeholder path a post takes before its picture arrives —
/// and the "data saved" figure in the composer is a real number rather than a
/// decoration. Counts are derived from the edges and documents below, never
/// hand-written, so the graph cannot contradict the profile stats.
Map<String, Map<String, Map<String, Object?>>> localSeedDocuments({DateTime? now}) {
  final at = now ?? DateTime.now();
  DateTime agoMinutes(int m) => at.subtract(Duration(minutes: m));
  DateTime agoHours(int h) => at.subtract(Duration(hours: h));
  DateTime agoDays(int d) => at.subtract(Duration(days: d));

  const demoUid = 'u_selam';

  final users = <UserProfile>[
    UserProfile(uid: demoUid, displayName: 'Selam Bekele', phone: localDemoPhone(), bio: 'Addis Ababa · photography and coffee', languageCode: 'am'),
    UserProfile(uid: 'u_dawit', displayName: 'Dawit Tesfaye', bio: 'Developer in Addis', languageCode: 'en'),
    UserProfile(uid: 'u_hiwot', displayName: 'Hiwot Alemu', bio: 'ጋቢ ሻይ · designer', languageCode: 'am'),
    UserProfile(uid: 'u_mulu', displayName: 'Mulu Girma', bio: 'Bahir Dar · lake and birds', languageCode: 'en'),
    UserProfile(uid: 'u_yonas', displayName: 'Yonas Haile', bio: 'Runner', languageCode: 'en'),
    UserProfile(uid: 'u_beth', displayName: 'Bethlehem Assefa', bio: 'Books, Amharic and vinyl', languageCode: 'am'),
    UserProfile(uid: 'u_kalki', displayName: 'Kalkidan Wolde', bio: 'Mekelle', languageCode: 'am'),
  ];

  MediaRef seedMedia(String id, int index, double aspect, int originalKb, int uploadKb) => MediaRef(
    id: 'seed/$id-$index',
    aspectRatio: aspect,
    originalBytes: originalKb * 1024,
    uploadedBytes: uploadKb * 1024,
    thumbBytes: uploadKb * 1024 ~/ 6,
  );

  final posts = <Post>[
    Post(postId: 'p_01', authorUid: 'u_hiwot', authorName: 'Hiwot Alemu', caption: 'Morning light over Entoto. የተፈጥሮ ብርሃን ምንም አይነት ማስተካከያ አይፈልግም።', media: [seedMedia('p_01', 0, 0.75, 2400, 340)], createdAt: agoMinutes(12), audience: Audience.everyone),
    Post(postId: 'p_02', authorUid: 'u_dawit', authorName: 'Dawit Tesfaye', caption: 'Shipped the offline queue today. Messages now survive a dropped connection without duplicating.', createdAt: agoMinutes(48), audience: Audience.everyone),
    Post(postId: 'p_03', authorUid: 'u_mulu', authorName: 'Mulu Girma', caption: 'Blue Nile falls, and a boat that cost less than my data bundle this month', media: [seedMedia('p_03', 0, 1.33, 3100, 410), seedMedia('p_03', 1, 1.0, 1900, 260)], createdAt: agoHours(3), audience: Audience.everyone),
    Post(postId: 'p_04', authorUid: demoUid, authorName: 'Selam Bekele', caption: 'ቡና ሲፈላ ጊዜው ይቆጥራል ☕', media: [seedMedia('p_04', 0, 1.0, 1600, 210)], createdAt: agoHours(5), audience: Audience.everyone),
    Post(postId: 'p_05', authorUid: 'u_yonas', authorName: 'Yonas Haile', caption: '42km around Addis before the heat. Frame rate on my old phone is the only thing that let me down.', createdAt: agoHours(9), audience: Audience.followers),
    Post(postId: 'p_06', authorUid: 'u_beth', authorName: 'Bethlehem Assefa', caption: 'Found a first edition at the Merkato book corner. ሁለት ነገሮች ነውን የማስታወክል', media: [seedMedia('p_06', 0, 0.8, 2200, 300)], createdAt: agoHours(14), audience: Audience.everyone),
    Post(postId: 'p_07', authorUid: 'u_kalki', authorName: 'Kalkidan Wolde', caption: 'Tigray highlands, no filter, 12 seconds of video that took 3 MB instead of 18', media: [seedMedia('p_07', 0, 1.77, 4800, 720)], createdAt: agoHours(20), audience: Audience.everyone),
    Post(postId: 'p_08', authorUid: 'u_hiwot', authorName: 'Hiwot Alemu', caption: 'Type specimen for the Ge\'ez script — the vertical rhythm matters more than the letterforms', media: [seedMedia('p_08', 0, 1.0, 900, 120), seedMedia('p_08', 1, 1.0, 950, 130), seedMedia('p_08', 2, 1.0, 880, 118)], createdAt: agoDays(1), audience: Audience.everyone),
    Post(postId: 'p_09', authorUid: 'u_dawit', authorName: 'Dawit Tesfaye', caption: 'Security rules are the whole authorization layer when there is no server. Wrote them twice and tested both.', createdAt: agoDays(1).subtract(const Duration(hours: 6)), audience: Audience.followers),
    Post(postId: 'p_10', authorUid: 'u_mulu', authorName: 'Mulu Girma', caption: 'Fish market mornings', media: [seedMedia('p_10', 0, 1.5, 2600, 350)], createdAt: agoDays(2), audience: Audience.everyone),
    Post(postId: 'p_11', authorUid: demoUid, authorName: 'Selam Bekele', caption: 'Tested the story viewer on airplane mode mid-play. It holds.', createdAt: agoDays(2).subtract(const Duration(hours: 4)), audience: Audience.everyone),
    Post(postId: 'p_12', authorUid: 'u_yonas', authorName: 'Yonas Haile', caption: 'Race week. Downloading other people\'s videos is how I study pace.', media: [seedMedia('p_12', 0, 0.66, 2100, 280)], createdAt: agoDays(3), audience: Audience.everyone),
    Post(postId: 'p_13', authorUid: 'u_beth', authorName: 'Bethlehem Assefa', caption: 'Amharic first, English second — the interface should not force you to switch to be understood', createdAt: agoDays(4), audience: Audience.everyone),
    Post(postId: 'p_14', authorUid: 'u_kalki', authorName: 'Kalkidan Wolde', caption: 'Harar old town walls at dusk', media: [seedMedia('p_14', 0, 1.2, 3300, 440)], createdAt: agoDays(5), audience: Audience.everyone),
    Post(postId: 'p_15', authorUid: 'u_hiwot', authorName: 'Hiwot Alemu', caption: 'Reduced a 24MB upload to 3.1MB without anyone complaining about quality. That is the whole product.', createdAt: agoDays(6), audience: Audience.everyone),
    Post(postId: 'p_16', authorUid: 'u_dawit', authorName: 'Dawit Tesfaye', caption: 'Mid-range Android field test: 58fps scroll, no jank, no thermal throttle', createdAt: agoDays(7), audience: Audience.everyone),
  ];

  final reactions = <({String postId, String uid, String emoji})>[
    (postId: 'p_01', uid: demoUid, emoji: 'like'),
    (postId: 'p_01', uid: 'u_dawit', emoji: 'like'),
    (postId: 'p_01', uid: 'u_mulu', emoji: 'like'),
    (postId: 'p_03', uid: 'u_hiwot', emoji: 'like'),
    (postId: 'p_03', uid: demoUid, emoji: 'like'),
    (postId: 'p_04', uid: 'u_yonas', emoji: 'like'),
    (postId: 'p_07', uid: 'u_kalki', emoji: 'like'),
    (postId: 'p_08', uid: 'u_beth', emoji: 'like'),
    (postId: 'p_15', uid: demoUid, emoji: 'like'),
  ];

  final comments = <Comment>[
    Comment(commentId: 'c_01', postId: 'p_01', authorUid: 'u_dawit', authorName: 'Dawit Tesfaye', text: 'The colour here is unreal', createdAt: agoMinutes(9)),
    Comment(commentId: 'c_02', postId: 'p_01', authorUid: demoUid, authorName: 'Selam Bekele', text: 'በጣም ጥሩ! ሙላውን እየመሰለኝ ነው', createdAt: agoMinutes(7)),
    Comment(commentId: 'c_03', postId: 'p_03', authorUid: 'u_hiwot', authorName: 'Hiwot Alemu', text: 'Take me next time', createdAt: agoHours(2)),
    Comment(commentId: 'c_04', postId: 'p_08', authorUid: 'u_beth', authorName: 'Bethlehem Assefa', text: 'Which font is that for Ethiopic?', createdAt: agoHours(20)),
    Comment(commentId: 'c_05', postId: 'p_15', authorUid: demoUid, authorName: 'Selam Bekele', text: 'This is the feature that sold me', createdAt: agoDays(1)),
  ];

  final followerPairs = <({String follower, String following})>[
    (follower: demoUid, following: 'u_hiwot'),
    (follower: demoUid, following: 'u_dawit'),
    (follower: demoUid, following: 'u_mulu'),
    (follower: demoUid, following: 'u_beth'),
    (follower: demoUid, following: 'u_kalki'),
    (follower: 'u_hiwot', following: demoUid),
    (follower: 'u_dawit', following: demoUid),
    (follower: 'u_mulu', following: demoUid),
    (follower: 'u_mulu', following: 'u_hiwot'),
    (follower: 'u_yonas', following: demoUid),
    (follower: 'u_yonas', following: 'u_dawit'),
    (follower: 'u_beth', following: 'u_hiwot'),
    (follower: 'u_beth', following: 'u_kalki'),
    (follower: 'u_kalki', following: demoUid),
    (follower: 'u_kalki', following: 'u_mulu'),
  ];

  final likesPerPost = <String, int>{};
  for (final r in reactions) {
    likesPerPost[r.postId] = (likesPerPost[r.postId] ?? 0) + 1;
  }
  final commentsPerPost = <String, int>{};
  for (final c in comments) {
    commentsPerPost[c.postId] = (commentsPerPost[c.postId] ?? 0) + 1;
  }
  final postsPerAuthor = <String, int>{};
  for (final p in posts) {
    postsPerAuthor[p.authorUid] = (postsPerAuthor[p.authorUid] ?? 0) + 1;
  }
  final followersPerUser = <String, int>{};
  final followingPerUser = <String, int>{};
  for (final edge in followerPairs) {
    followersPerUser[edge.following] = (followersPerUser[edge.following] ?? 0) + 1;
    followingPerUser[edge.follower] = (followingPerUser[edge.follower] ?? 0) + 1;
  }

  final stories = <Story>[
    Story(
      storyId: 's_01',
      authorUid: demoUid,
      authorName: 'Selam Bekele',
      media: seedMedia('s_01', 0, 0.5625, 1800, 240),
      caption: 'Meskel bonfire evening',
      createdAt: agoHours(2),
      expiresAt: at.add(const Duration(hours: 22)),
    ),
    Story(
      storyId: 's_02',
      authorUid: 'u_hiwot',
      authorName: 'Hiwot Alemu',
      media: seedMedia('s_02', 0, 0.5625, 2000, 260),
      createdAt: agoHours(4),
      expiresAt: at.add(const Duration(hours: 20)),
      viewerUids: {demoUid},
    ),
    Story(
      storyId: 's_03',
      authorUid: 'u_mulu',
      authorName: 'Mulu Girma',
      media: seedMedia('s_03', 0, 0.5625, 1500, 190),
      caption: 'Boat repair day',
      createdAt: agoHours(6),
      expiresAt: at.add(const Duration(hours: 18)),
    ),
    // Already expired: the cleanup sweep has something real to delete on first
    // run, which is how the expiry path gets exercised.
    Story(
      storyId: 's_04',
      authorUid: 'u_dawit',
      authorName: 'Dawit Tesfaye',
      media: seedMedia('s_04', 0, 0.5625, 1700, 220),
      createdAt: agoDays(2),
      expiresAt: agoHours(2),
    ),
  ];

  final conversations = <Conversation>[
    Conversation(
      conversationId: 'u_dawit_u_selam',
      participantUids: const ['u_dawit', 'u_selam'],
      peer: const UserProfileRef(uid: 'u_dawit', displayName: 'Dawit Tesfaye'),
      lastMessage: 'Pushing the rules fix now',
      lastMessageAt: agoMinutes(26),
      lastSenderUid: 'u_dawit',
      unreadCounts: const {'u_selam': 2, 'u_dawit': 0},
    ),
    Conversation(
      conversationId: 'u_hiwot_u_selam',
      participantUids: const ['u_hiwot', 'u_selam'],
      peer: const UserProfileRef(uid: 'u_hiwot', displayName: 'Hiwot Alemu'),
      lastMessage: 'Send me the specimen when you can',
      lastMessageAt: agoHours(7),
      lastSenderUid: demoUid,
      unreadCounts: const {'u_selam': 0, 'u_hiwot': 0},
    ),
  ];

  final messages = <Message>[
    Message(messageId: 'm_01', conversationId: 'u_dawit_u_selam', senderUid: 'u_dawit', recipientUid: demoUid, text: 'Are the story thumbnails 320px now?', createdAt: agoMinutes(58)),
    Message(messageId: 'm_02', conversationId: 'u_dawit_u_selam', senderUid: demoUid, recipientUid: 'u_dawit', text: 'Yes, and lists never fetch the original', createdAt: agoMinutes(52)),
    Message(messageId: 'm_03', conversationId: 'u_dawit_u_selam', senderUid: 'u_dawit', recipientUid: demoUid, text: 'Good. That halves the bill', createdAt: agoMinutes(41)),
    Message(messageId: 'm_04', conversationId: 'u_dawit_u_selam', senderUid: 'u_dawit', recipientUid: demoUid, text: 'Pushing the rules fix now', createdAt: agoMinutes(26)),
    Message(messageId: 'm_05', conversationId: 'u_hiwot_u_selam', senderUid: 'u_hiwot', recipientUid: demoUid, text: 'The Ge\'ez spacing looks right finally', createdAt: agoHours(8)),
    Message(messageId: 'm_06', conversationId: 'u_hiwot_u_selam', senderUid: demoUid, recipientUid: 'u_hiwot', text: 'Send me the specimen when you can', createdAt: agoHours(7)),
  ];

  final notifications = <AppNotification>[
    AppNotification(id: 'n_01', recipientUid: demoUid, type: NotificationType.message, actorName: 'Dawit Tesfaye', actorUid: 'u_dawit', body: 'Pushing the rules fix now', conversationId: 'u_dawit_u_selam', createdAt: agoMinutes(26)),
    AppNotification(id: 'n_02', recipientUid: demoUid, type: NotificationType.like, actorName: 'Hiwot Alemu', actorUid: 'u_hiwot', body: 'liked your post', postId: 'p_04', createdAt: agoHours(3)),
    AppNotification(id: 'n_03', recipientUid: demoUid, type: NotificationType.follow, actorName: 'Kalkidan Wolde', actorUid: 'u_kalki', body: 'started following you', createdAt: agoHours(6)),
    AppNotification(id: 'n_04', recipientUid: demoUid, type: NotificationType.comment, actorName: 'Bethlehem Assefa', actorUid: 'u_beth', body: 'Read your note on data cost twice', postId: 'p_11', createdAt: agoDays(1)),
    AppNotification(id: 'n_05', recipientUid: demoUid, type: NotificationType.mention, actorName: 'Mulu Girma', actorUid: 'u_mulu', body: 'mentioned you', postId: 'p_10', readAt: agoHours(2), createdAt: agoDays(2)),
  ];

    return {
    'users': {
      for (final user in users)
        user.uid: UserProfile(
          uid: user.uid,
          displayName: user.displayName,
          bio: user.bio,
          phone: user.phone,
          languageCode: user.languageCode,
          followersCount: followersPerUser[user.uid] ?? 0,
          followingCount: followingPerUser[user.uid] ?? 0,
          postsCount: postsPerAuthor[user.uid] ?? 0,
        ).toMap(),
    },
    'posts': {
      for (final post in posts)
        post.postId: post.copyWith(
          likesCount: likesPerPost[post.postId] ?? 0,
          commentsCount: commentsPerPost[post.postId] ?? 0,
        ).toMap(),
    },
    'reactions': {
      for (final r in reactions)
        '${r.postId}_${r.uid}': {'postId': r.postId, 'uid': r.uid, 'emoji': r.emoji, 'createdAt': agoHours(3)},
    },
    'comments': {
      for (final comment in comments) comment.commentId: comment.toMap(),
    },
    'follows': {
      for (final edge in followerPairs)
        '${edge.follower}_${edge.following}': FollowEdge(
          followerUid: edge.follower,
          followingUid: edge.following,
          createdAt: agoDays(3),
        ).toMap(),
    },
    'stories': {
      for (final story in stories) story.storyId: story.toMap(),
    },
    'conversations': {
      for (final conversation in conversations) conversation.conversationId: conversation.toMap(),
    },
    'messages': {
      for (final message in messages) message.messageId: message.toMap(),
    },
    'notifications': {
      for (final notification in notifications) notification.id: notification.toMap(),
    },
  };
}

/// The account the sign-in screen can prefill, so the demo content has an owner.
String localDemoPhone() => '+251911223344';
