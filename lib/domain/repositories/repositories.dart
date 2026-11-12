import 'dart:typed_data';

import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/media.dart';
import 'package:liyu_social/domain/models/notification.dart';
import 'package:liyu_social/domain/models/post.dart';
import 'package:liyu_social/domain/models/story.dart';
import 'package:liyu_social/domain/models/user.dart';

/// The client talks to these interfaces, never to an SDK directly.
///
/// Two implementations exist: a Firebase backend and a local on-device backend.
/// The local one is what lets the app build, run and be widget-tested without
/// any project credentials, and it enforces the same access decisions the
/// Firestore rules express — so an authorization mistake surfaces in tests
/// rather than only in production.

/// Which backend the running app is wired to.
enum BackendMode {
  /// Auth + Firestore + Storage + FCM. Requires a generated FirebaseOptions.
  firebase,

  /// On-device store with the same contracts. No credentials needed.
  local;

  static BackendMode fromString(String? raw) => raw == 'firebase' ? BackendMode.firebase : BackendMode.local;
}

/// Reports whether the client believes it can reach the backend. The offline
/// write queue drains when this flips to online.
abstract class ConnectionMonitor {
  Stream<bool> get changes;
  bool get online;

  /// Hook for demoing and testing reconnect behaviour without airplane mode.
  void setSimulatedOffline(bool offline);
}

abstract class AuthRepository {
  Stream<UserProfile?> authState();

  /// Phone sign-in. [OtpChallenge.devCode] is only populated by the local
  /// backend, which cannot send a real SMS; a Firebase build delivers the code
  /// over SMS and leaves it null.
  Future<OtpChallenge> sendOtp(String phone);

  Future<UserProfile> signInWithOtp({required OtpChallenge challenge, required String code});

  Future<UserProfile> signInWithEmail({required String email, required String password});

  Future<UserProfile> register({
    required String displayName,
    String? phone,
    String? email,
    String? password,
    String languageCode = 'en',
  });

  Future<UserProfile> updateProfile(UserProfile profile);

  Future<void> signOut();
}

class OtpChallenge {
  const OtpChallenge({required this.verificationId, this.devCode, this.expiresIn});

  final String verificationId;
  final String? devCode;
  final Duration? expiresIn;
}

abstract class FeedRepository {
  /// Live first page. Backed by a limited snapshot listener so the feed updates
  /// without a manual refresh.
  Stream<List<Post>> watchFeed({int limit = 12});

  Stream<List<Post>> watchAuthorPosts(String authorUid, {int limit = 30});

  /// Cursor page for infinite scroll. A (createdAt, id) pair is what Firestore
  /// can order and seek on without offset reads.
  Future<List<Post>> loadOlder({required PostCursor cursor, int limit = 12});

  /// One post by id, for a share link or a tray tap that points outside the
  /// reader's current window. Null means the post is gone; a reader the rules
  /// refuse throws `permission-denied`, the way a Firestore `get` does.
  Future<Post?> loadPost(String postId);

  /// [media] holds references that already went through the pipeline and were
  /// uploaded, so publishing writes documents and never starts a transfer.
  Future<Post> publish({
    required UserProfileRef author,
    List<MediaRef> media = const [],
    String caption = '',
    Audience audience = Audience.everyone,
    List<String> mentions = const [],
  });

  Future<void> deletePost(String postId);

  /// Returns the reaction now active for [uid], or null when it was cleared.
  Future<String?> toggleReaction({required String postId, required String uid, String emoji = 'like'});

  Stream<String?> watchMyReaction({required String postId, required String uid});

  Stream<List<Comment>> watchComments(String postId);

  Future<Comment> addComment({
    required Post post,
    required UserProfileRef author,
    required String text,
    List<String> mentions = const [],
  });

  Stream<List<UserProfile>> suggestions({int limit = 8});
}

class PostCursor {
  const PostCursor({required this.createdAt, required this.postId});

  final DateTime createdAt;
  final String postId;
}

abstract class StoryRepository {
  /// Active stories for [uid] and the accounts they follow.
  Stream<List<Story>> watchActive({required String uid});

  Future<Story> publish({
    required UserProfileRef author,
    required MediaRef media,
    String caption = '',
    Duration ttl = const Duration(hours: 24),
  });

  Future<void> markViewed({required String storyId, required String uid});
}

abstract class MessagingRepository {
  Stream<List<Conversation>> watchInbox(String uid);

  Stream<List<Message>> watchThread(String conversationId, {int limit = 50});

  Future<String> openConversationWith({required String myUid, required UserProfileRef peer});

  /// Idempotent on [Message.messageId], so a retry after a dropped connection
  /// cannot create a second copy.
  Future<Message> send(Message message);

  Future<Message> retry(Message message);

  Future<void> markRead({required String conversationId, required String uid});

  Future<List<UserProfile>> searchPeople(String query, {int limit = 10});
}

abstract class ProfileRepository {
  Future<UserProfile?> load(String uid);

  Stream<UserProfile?> watch(String uid);

  Stream<bool> watchFollowing({required String followerUid, required String targetUid});

  Future<void> setFollow({required String followerUid, required String targetUid, required bool following});

  Future<void> setBlock({required String blockerUid, required String blockedUid, required bool blocked});

  Stream<List<UserProfile>> watchConnections({required String uid, required ConnectionKind kind});
}

enum ConnectionKind { followers, following }

abstract class NotificationRepository {
  Stream<List<AppNotification>> watch(String uid, {int limit = 30});

  Future<void> markRead(String id);

  Future<void> markAllRead(String uid);

  Future<void> registerDeviceToken({required String uid, required String token});
}

/// A file chosen by the user, decoupled from any picker plugin.
class SourceFile {
  const SourceFile({required this.path, required this.name, required this.sizeBytes, this.bytes});

  final String path;
  final String name;
  final int sizeBytes;

  /// Read eagerly on platforms without a filesystem (web), otherwise loaded
  /// from [path] on demand.
  final Uint8List? bytes;
}

/// Client-side media pipeline plus the upload that follows it. Kept as one
/// interface because the thumbnail is generated from the bytes that get
/// uploaded, and the pair has to stay consistent.
abstract class MediaRepository {
  /// Downscale and compress on-device. Never touches the network.
  Future<PreparedMedia> prepare(SourceFile file, {int maxDimension = 1280, int quality = 80});

  /// Upload the prepared pair under [ownerUid]'s own path prefix and return a
  /// resolvable reference. Progress is 0..1.
  Future<MediaRef> upload({
    required String ownerUid,
    required PreparedMedia prepared,
    required MediaPurpose purpose,
    void Function(double progress)? onProgress,
  });

  Future<void> delete(String mediaId);
}

enum MediaPurpose { post, story, avatar, chat }
