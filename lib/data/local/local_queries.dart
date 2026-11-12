import 'package:liyu_social/data/local/local_store.dart';
import 'package:liyu_social/domain/access_rules.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/post.dart';
import 'package:liyu_social/domain/models/story.dart';
import 'package:liyu_social/domain/models/user.dart';

/// Read helpers shared by every local repository, so the graph and block
/// lookups are resolved the same way regardless of which screen asked.
class LocalQueries {
  LocalQueries(this._store);

  final LocalStore _store;

  UserProfile? user(String uid) {
    final doc = _store.doc('users', uid);
    return doc == null ? null : UserProfile.fromMap(doc);
  }

  List<UserProfile> allUsers() => _store.all('users').map(UserProfile.fromMap).toList();

  /// Uids this account follows. `follows` stores one edge per direction, so
  /// both directions of the question are answerable without a second query.
  Set<String> followingOf(String uid) => _edgeUids(_store.all('follows'), 'followerUid', uid);

  Set<String> followersOf(String uid) => _edgeUids(_store.all('follows'), 'followingUid', uid);

  bool follows({required String followerUid, required String followingUid}) =>
      _store.doc('follows', '${followerUid}_$followingUid') != null;

  Set<String> blockingOf(String uid) => user(uid)?.blocking ?? const {};

  List<Post> postsSortedDesc() {
    final posts = _store.all('posts').map(Post.fromMap).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return posts;
  }

  List<Story> storiesSortedAsc() {
    final stories = _store.all('stories').map(Story.fromMap).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return stories;
  }

  List<Comment> commentsFor(String postId) {
    final comments = _store
        .all('comments')
        .where((doc) => doc['postId'] == postId)
        .map(Comment.fromMap)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return comments;
  }

  String? myReactionEmoji({required String postId, required String uid}) {
    final doc = _store.doc('reactions', '${postId}_$uid');
    return doc?['emoji'] as String?;
  }

  /// Posts a reader is allowed to see, per `AccessRules`. Computed once per
  /// snapshot so a list build never re-evaluates the graph.
  List<Post> visiblePosts({required String? viewerUid}) {
    if (viewerUid == null) {
      return postsSortedDesc().where((p) => p.audience == Audience.everyone).toList();
    }
    final viewer = user(viewerUid);
    final viewerBlocking = viewer?.blocking ?? const <String>{};
    return postsSortedDesc().where((post) {
      final authorBlocking = blockingOf(post.authorUid);
      return AccessRules.canReadPost(
        post: post,
        viewerUid: viewerUid,
        viewerBlocking: viewerBlocking,
        authorBlocking: authorBlocking,
        viewerFollowsAuthor: follows(followerUid: viewerUid, followingUid: post.authorUid),
      );
    }).toList();
  }

  static Set<String> _edgeUids(List<Map<String, Object?>> docs, String field, String uid) =>
      docs.where((doc) => doc[field] == uid).map((doc) => doc[_otherField(field)] as String).toSet();

  static String _otherField(String field) => field == 'followerUid' ? 'followingUid' : 'followerUid';
}
