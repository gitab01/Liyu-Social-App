import 'package:flutter_test/flutter_test.dart';
import 'package:liyu_social/domain/access_rules.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/media.dart';
import 'package:liyu_social/domain/models/post.dart';
import 'package:liyu_social/domain/models/story.dart';
import 'package:liyu_social/domain/models/user.dart';

/// `firestore.rules` restates these predicates and the emulator suite asserts the
/// same cases, so a divergence is a real authorization bug rather than a
/// theoretical one. These are the cases both sides must agree on.
void main() {
  final now = DateTime(2026, 4, 5, 12);

  Post post({Audience audience = Audience.everyone, String authorUid = 'u_author'}) => Post(
    postId: 'p_1',
    authorUid: authorUid,
    authorName: 'Author',
    audience: audience,
    createdAt: now,
  );

  Story story({DateTime? expiresAt, String authorUid = 'u_author'}) => Story(
    storyId: 's_1',
    authorUid: authorUid,
    authorName: 'Author',
    media: const MediaRef(id: 'm_1'),
    createdAt: now,
    expiresAt: expiresAt ?? now.add(const Duration(hours: 6)),
  );

  group('canReadPost', () {
    test('a signed-out reader sees public posts only', () {
      expect(AccessRules.canReadPost(post: post(), viewerUid: null), isTrue);
      expect(
        AccessRules.canReadPost(post: post(audience: Audience.followers), viewerUid: null),
        isFalse,
      );
    });

    test('the author always reads their own post, even followers-only', () {
      expect(
        AccessRules.canReadPost(
          post: post(audience: Audience.followers),
          viewerUid: 'u_author',
        ),
        isTrue,
      );
    });

    test('a followers-only post needs a follow edge', () {
      const restricted = Audience.followers;
      expect(
        AccessRules.canReadPost(
          post: post(audience: restricted),
          viewerUid: 'u_viewer',
        ),
        isFalse,
      );
      expect(
        AccessRules.canReadPost(
          post: post(audience: restricted),
          viewerUid: 'u_viewer',
          viewerFollowsAuthor: true,
        ),
        isTrue,
      );
    });

    test('a block hides in both directions, from the viewer or the author', () {
      expect(
        AccessRules.canReadPost(
          post: post(),
          viewerUid: 'u_viewer',
          viewerBlocking: {'u_author'},
        ),
        isFalse,
      );
      expect(
        AccessRules.canReadPost(
          post: post(),
          viewerUid: 'u_viewer',
          authorBlocking: {'u_viewer'},
        ),
        isFalse,
      );
    });
  });

  test('only the author writes a post', () {
    expect(AccessRules.canWritePost(post: post(), uid: 'u_author'), isTrue);
    expect(AccessRules.canWritePost(post: post(), uid: 'u_viewer'), isFalse);
  });

  test('commenting requires being able to see the post', () {
    expect(
      AccessRules.canCommentOn(post: post(audience: Audience.followers), viewerUid: null),
      isFalse,
    );
    expect(
      AccessRules.canCommentOn(
        post: post(audience: Audience.followers),
        viewerUid: 'u_viewer',
        viewerFollowsAuthor: true,
      ),
      isTrue,
    );
  });

  group('stories', () {
    test('expire for everyone, including the author, once the deadline passes', () {
      final expired = story(expiresAt: now.subtract(const Duration(minutes: 1)));
      expect(
        AccessRules.canReadStory(story: expired, viewerUid: 'u_author', now: now),
        isFalse,
      );
      expect(
        AccessRules.canReadStory(
          story: story(expiresAt: now.add(const Duration(seconds: 1))),
          viewerUid: 'u_author',
          now: now,
        ),
        isTrue,
      );
    });

    test('are followers-only while alive, with no public branch', () {
      expect(
        AccessRules.canReadStory(story: story(), viewerUid: 'u_viewer', now: now),
        isFalse,
      );
      expect(
        AccessRules.canReadStory(story: story(), viewerUid: 'u_viewer', now: now, viewerFollowsAuthor: true),
        isTrue,
      );
    });

    test('a blocked author is not readable even by a follower', () {
      expect(
        AccessRules.canReadStory(
          story: story(),
          viewerUid: 'u_viewer',
          now: now,
          viewerBlocking: {'u_author'},
          viewerFollowsAuthor: true,
        ),
        isFalse,
      );
    });

    test('only the author writes a story', () {
      expect(AccessRules.canWriteStory(story: story(), uid: 'u_author'), isTrue);
      expect(AccessRules.canWriteStory(story: story(), uid: 'u_viewer'), isFalse);
    });
  });

  group('messages', () {
    final conversation = Conversation(
      conversationId: 'u_a_u_b',
      participantUids: const ['u_a', 'u_b'],
      peer: const UserProfileRef(uid: 'u_b', displayName: 'B'),
    );

    test('the two participants read a message, nobody else', () {
      expect(AccessRules.canReadMessage(senderUid: 'u_a', recipientUid: 'u_b', uid: 'u_a'), isTrue);
      expect(AccessRules.canReadMessage(senderUid: 'u_a', recipientUid: 'u_b', uid: 'u_b'), isTrue);
      expect(AccessRules.canReadMessage(senderUid: 'u_a', recipientUid: 'u_b', uid: 'u_c'), isFalse);
    });

    test('a thread is only listable by its participants', () {
      expect(AccessRules.canReadConversation(conversation: conversation, uid: 'u_a'), isTrue);
      expect(AccessRules.canReadConversation(conversation: conversation, uid: 'u_c'), isFalse);
    });
  });

  group('media', () {
    test('a client writes under its own uid prefix only', () {
      final path = AccessRules.mediaPathFor(uid: 'u_a', purpose: 'post', mediaId: 'm_1');
      expect(path, 'users/u_a/post/m_1');
      expect(AccessRules.canWriteMediaPath(path: path, uid: 'u_a'), isTrue);
      expect(AccessRules.canWriteMediaPath(path: path, uid: 'u_b'), isFalse);
    });
  });

  group('profile and graph', () {
    final profile = UserProfile(uid: 'u_a', displayName: 'A', blocking: const {'u_b'});

    test('a profile needs a signed-in viewer and respects blocks both ways', () {
      expect(AccessRules.canReadProfile(profile: profile, viewerUid: null), isFalse);
      expect(AccessRules.canReadProfile(profile: profile, viewerUid: 'u_a'), isTrue);
      expect(AccessRules.canReadProfile(profile: profile, viewerUid: 'u_c'), isTrue);
      expect(AccessRules.canReadProfile(profile: profile, viewerUid: 'u_b'), isFalse);
      expect(
        AccessRules.canReadProfile(profile: profile, viewerUid: 'u_c', viewerBlocking: {'u_a'}),
        isFalse,
      );
    });

    test('you own your outgoing follow edge, never someone else', () {
      final mine = FollowEdge(followerUid: 'u_a', followingUid: 'u_b', createdAt: now);
      final theirs = FollowEdge(followerUid: 'u_c', followingUid: 'u_b', createdAt: now);
      expect(AccessRules.canWriteFollowEdge(edge: mine, uid: 'u_a'), isTrue);
      expect(AccessRules.canWriteFollowEdge(edge: theirs, uid: 'u_a'), isFalse);
    });

    test('a reaction belongs to its reactor', () {
      expect(AccessRules.canWriteReaction(reactorUid: 'u_a', uid: 'u_a'), isTrue);
      expect(AccessRules.canWriteReaction(reactorUid: 'u_a', uid: 'u_b'), isFalse);
    });
  });
}
