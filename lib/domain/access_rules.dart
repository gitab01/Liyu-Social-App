import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/post.dart';
import 'package:liyu_social/domain/models/story.dart';
import 'package:liyu_social/domain/models/user.dart';

/// The one place read/write authorization is expressed as plain Dart.
///
/// With no server tier, Firestore security rules are the only gate — and rules
/// are far more awkward to test than functions. So the local backend enforces
/// exactly these predicates, `firestore.rules` restates them, and a rules
/// emulator suite asserts the same cases on both sides. A divergence shows up
/// as a failing test rather than an exploit.
///
/// `blocking` sets are the author's and viewer's own block lists: a block hides
/// content in both directions.
class AccessRules {
  const AccessRules._();

  static bool canReadPost({
    required Post post,
    required String? viewerUid,
    Set<String> viewerBlocking = const {},
    Set<String> authorBlocking = const {},
    bool viewerFollowsAuthor = false,
  }) {
    if (viewerUid == null) return post.audience == Audience.everyone;
    if (viewerUid == post.authorUid) return true;
    if (viewerBlocking.contains(post.authorUid) || authorBlocking.contains(viewerUid)) return false;
    return post.audience == Audience.everyone || viewerFollowsAuthor;
  }

  /// Only the author may mutate a post.
  static bool canWritePost({required Post post, required String uid}) => post.authorUid == uid;

  /// Commenting requires being able to see the post at all.
  static bool canCommentOn({
    required Post post,
    required String? viewerUid,
    Set<String> viewerBlocking = const {},
    Set<String> authorBlocking = const {},
    bool viewerFollowsAuthor = false,
  }) {
    if (viewerUid == null) return false;
    return canReadPost(
      post: post,
      viewerUid: viewerUid,
      viewerBlocking: viewerBlocking,
      authorBlocking: authorBlocking,
      viewerFollowsAuthor: viewerFollowsAuthor,
    );
  }

  static bool canReadStory({
    required Story story,
    required String? viewerUid,
    required DateTime now,
    Set<String> viewerBlocking = const {},
    Set<String> authorBlocking = const {},
    bool viewerFollowsAuthor = false,
  }) {
    if (viewerUid == null || story.isExpiredAt(now)) return false;
    if (viewerUid == story.authorUid) return true;
    if (viewerBlocking.contains(story.authorUid) || authorBlocking.contains(viewerUid)) return false;
    return viewerFollowsAuthor;
  }

  static bool canWriteStory({required Story story, required String uid}) => story.authorUid == uid;

  /// A message is readable by its two participants only.
  static bool canReadMessage({required String senderUid, required String recipientUid, required String uid}) =>
      uid == senderUid || uid == recipientUid;

  static bool canReadConversation({required Conversation conversation, required String uid}) =>
      conversation.participantUids.contains(uid);

  /// A client may only write under its own uid prefix, which is what stops one
  /// account from overwriting another's media.
  static String mediaPathFor({required String uid, required String purpose, required String mediaId}) =>
      'users/$uid/$purpose/$mediaId';

  static bool canWriteMediaPath({required String path, required String uid}) => path.startsWith('users/$uid/');

  static bool canReadProfile({required UserProfile profile, required String? viewerUid, Set<String> viewerBlocking = const {}}) {
    if (viewerUid == null) return false;
    if (viewerUid == profile.uid) return true;
    return !viewerBlocking.contains(profile.uid) && !profile.blocking.contains(viewerUid);
  }

  /// Following is a graph edge a client owns: you may create or drop your own
  /// edge, never someone else's.
  static bool canWriteFollowEdge({required FollowEdge edge, required String uid}) => edge.followerUid == uid;

  static bool canWriteReaction({required String reactorUid, required String uid}) => reactorUid == uid;
}
