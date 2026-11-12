import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/notification.dart';
import 'package:liyu_social/domain/models/post.dart';
import 'package:liyu_social/domain/models/story.dart';
import 'package:liyu_social/domain/models/user.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// Live data for every screen. Feature UI reads these and nothing else, which
/// is what keeps a feed row from rebuilding the whole list.

const int feedPageSize = 12;

/// The live head of the feed: a bounded listener, so new posts from people you
/// follow arrive without a refresh and without an unbounded read.
final feedHeadProvider = StreamProvider<List<Post>>(
  (ref) => ref.watch(feedRepositoryProvider).watchFeed(limit: feedPageSize),
);

class OlderState {
  const OlderState({this.items = const [], this.endReached = false, this.loading = false});

  final List<Post> items;
  final bool endReached;
  final bool loading;

  OlderState copyWith({List<Post>? items, bool? endReached, bool? loading}) =>
      OlderState(items: items ?? this.items, endReached: endReached ?? this.endReached, loading: loading ?? this.loading);
}

/// Cursor pages below the live head, appended as the user reaches the end.
/// Prefetching the next page one row early is what hides a slow connection.
class OlderPostsController extends AutoDisposeAsyncNotifier<OlderState> {
  @override
  Future<OlderState> build() async => const OlderState();

  Future<void> loadMore() async {
    final current = state.valueOrNull ?? const OlderState();
    if (current.loading || current.endReached) return;

    final head = ref.read(feedHeadProvider).valueOrNull ?? const [];
    final boundary = current.items.isNotEmpty ? current.items.last : (head.isNotEmpty ? head.last : null);
    if (boundary == null) return;

    state = AsyncData(current.copyWith(loading: true));
    try {
      final page = await ref.read(feedRepositoryProvider).loadOlder(
        cursor: PostCursor(createdAt: boundary.createdAt, postId: boundary.postId),
        limit: feedPageSize,
      );
      final merged = [...current.items, ...page.where((p) => !current.items.any((e) => e.postId == p.postId))];
      state = AsyncData(OlderState(items: merged, endReached: page.length < feedPageSize));
    } on Object catch (error, stack) {
      state = AsyncError(error, stack);
    }
  }
}

final olderPostsProvider = AsyncNotifierProvider.autoDispose<OlderPostsController, OlderState>(
  OlderPostsController.new,
);

/// What the list actually renders: live head then older pages, newest first,
/// with the boundary document deduplicated.
final feedProvider = Provider<List<Post>>((ref) {
  final head = ref.watch(feedHeadProvider).valueOrNull ?? const <Post>[];
  final older = ref.watch(olderPostsProvider).valueOrNull?.items ?? const <Post>[];
  final merged = <String, Post>{for (final p in head) p.postId: p};
  for (final p in older) {
    merged.putIfAbsent(p.postId, () => p);
  }
  final list = merged.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return list;
});

final feedIsLoadingProvider = Provider<bool>(
  (ref) => ref.watch(feedHeadProvider).isLoading || ref.watch(olderPostsProvider).isLoading,
);

final feedEndReachedProvider = Provider<bool>(
  (ref) => ref.watch(olderPostsProvider).valueOrNull?.endReached ?? false,
);

/// Per-reader reaction state, resolved outside the post document. One small
/// read per visible row, which is cheaper than rebuilding a feed on every like.
final myReactionProvider = StreamProvider.family<String?, String>((ref, postId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(feedRepositoryProvider).watchMyReaction(postId: postId, uid: uid);
});

final commentsProvider = StreamProvider.family<List<Comment>, String>(
  (ref, postId) => ref.watch(feedRepositoryProvider).watchComments(postId),
);

final suggestionsProvider = StreamProvider<List<UserProfile>>(
  (ref) => ref.watch(feedRepositoryProvider).suggestions(limit: 8),
);

/// Active stories, with expired ones dropped client-side so a document that has
/// not been reaped yet cannot still be opened.
final storiesProvider = StreamProvider<List<Story>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  final now = DateTime.now();
  return ref.watch(storyRepositoryProvider).watchActive(uid: uid).map(
    (stories) => stories.where((s) => !s.isExpiredAt(now)).toList(),
  );
});

final storyGroupsProvider = Provider<List<StoryGroup>>((ref) {
  final stories = ref.watch(storiesProvider).valueOrNull ?? const <Story>[];
  final byAuthor = <String, List<Story>>{};
  for (final story in stories) {
    byAuthor.putIfAbsent(story.authorUid, () => []).add(story);
  }
  final groups = byAuthor.entries
      .map((e) => StoryGroup(authorUid: e.key, authorName: e.value.first.authorName, stories: e.value))
      .toList()
    ..sort((a, b) => b.latestAt.compareTo(a.latestAt));
  return groups;
});

final inboxProvider = StreamProvider<List<Conversation>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(messagingRepositoryProvider).watchInbox(uid);
});

final inboxUnreadProvider = Provider<int>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return 0;
  final conversations = ref.watch(inboxProvider).valueOrNull ?? const [];
  return conversations.fold(0, (sum, c) => sum + c.unreadFor(uid));
});

/// Ordered oldest → newest; the thread view reverses for scrolling.
final threadProvider = StreamProvider.family<List<Message>, String>(
  (ref, conversationId) => ref.watch(messagingRepositoryProvider).watchThread(conversationId),
);

final profileProvider = StreamProvider.family<UserProfile?, String>(
  (ref, uid) => ref.watch(profileRepositoryProvider).watch(uid),
);

final followingStateProvider = StreamProvider.family<bool, String>((ref, targetUid) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(false);
  return ref.watch(profileRepositoryProvider).watchFollowing(followerUid: uid, targetUid: targetUid);
});

final authorPostsProvider = StreamProvider.family<List<Post>, String>(
  (ref, uid) => ref.watch(feedRepositoryProvider).watchAuthorPosts(uid),
);

/// One post, for a route that can point outside the reader's feed window.
final postProvider = FutureProvider.family<Post?, String>(
  (ref, postId) => ref.watch(feedRepositoryProvider).loadPost(postId),
);

/// Followers or following, as the graph currently allows it to be read.
final connectionsProvider = StreamProvider.family<List<UserProfile>, ({String uid, ConnectionKind kind})>(
  (ref, args) => ref.watch(profileRepositoryProvider).watchConnections(uid: args.uid, kind: args.kind),
);

final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(notificationRepositoryProvider).watch(uid);
});

final unreadNotificationsProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).valueOrNull ?? const [];
  return list.where((n) => n.isUnread).length;
});

final peopleSearchProvider = FutureProvider.family<List<UserProfile>, String>((ref, query) {
  if (query.trim().isEmpty) return Future.value(const []);
  return ref.watch(messagingRepositoryProvider).searchPeople(query.trim());
});
