import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/providers/feature_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/core/utils/formatters.dart';
import 'package:liyu_social/core/widgets/layout.dart';
import 'package:liyu_social/core/widgets/media_view.dart';
import 'package:liyu_social/core/widgets/state_views.dart';
import 'package:liyu_social/core/widgets/user_avatar.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/post.dart';
import 'package:liyu_social/domain/models/user.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';
import 'package:liyu_social/features/profile/widgets/follow_button.dart';

/// A profile: the person, their counts, and the grid of what they posted.
///
/// The same widget serves the signed-in account and a stranger. Which one it is
/// decides the actions, not the layout — a profile you do not own still has to
/// answer "who is this and what have they posted", and it does so from the same
/// reads. Blocked accounts never reach this screen as a tile, and the rules
/// refuse their documents anyway.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({required this.uid, super.key});

  /// The shell tab: whoever is signed in is the subject.
  const ProfileScreen.self({super.key}) : uid = null;

  final String? uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final me = ref.watch(currentUidProvider);
    final subjectUid = uid ?? me;
    if (subjectUid == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t.profile)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isMe = subjectUid == me;
    final profile = ref.watch(profileProvider(subjectUid));

    return Scaffold(
      appBar: AppBar(
        title: Text(isMe ? t.profile : t.people),
        actions: [
          if (isMe)
            IconButton(
              tooltip: t.settings,
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.push('/settings'),
            )
          else
            _BlockMenu(subjectUid: subjectUid),
        ],
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => FailureView(error: error, onRetry: () => ref.invalidate(profileProvider(subjectUid))),
        data: (person) {
          if (person == null) {
            return EmptyState(title: t.nothingNewHere, icon: Icons.person_off_outlined);
          }
          return _ProfileBody(person: person, isMe: isMe);
        },
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.person, required this.isMe});

  final UserProfile person;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final locale = Localizations.localeOf(context).languageCode;
    final posts = ref.watch(authorPostsProvider(person.uid)).valueOrNull ?? const <Post>[];

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        ContentShell(
          padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.l, AppSpacing.l, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatar(name: person.displayName, photoUrl: person.photoUrl, size: 72),
                  const SizedBox(width: AppSpacing.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        _StatRow(person: person, locale: locale),
                      ],
                    ),
                  ),
                ],
              ),
              if (person.bio.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.m),
                Text(person.bio, style: Theme.of(context).textTheme.bodyMedium),
              ],
              const SizedBox(height: AppSpacing.l),
              _Actions(person: person, isMe: isMe),
            ],
          ),
        ),
        SectionHeader(title: '${t.posts} · ${posts.length}'),
        if (posts.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, AppSpacing.xl),
            child: Text(t.noPostsYet, style: Theme.of(context).textTheme.bodyMedium),
          )
        else
          ContentShell(
            padding: EdgeInsets.zero,
            child: LayoutBuilder(
              builder: (context, constraints) => _PostGrid(
                posts: posts,
                columns: constraints.maxWidth > 720 ? 5 : 3,
              ),
            ),
          ),
      ],
    );
  }
}

/// Three numbers, each one a route into the graph behind it.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.person, required this.locale});

  final UserProfile person;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Wrap(
      spacing: AppSpacing.l,
      runSpacing: AppSpacing.xs,
      children: [
        MetaText(text: '${compactCount(person.postsCount, languageCode: locale)} ${t.posts}'),
        _ConnectionStat(
          uid: person.uid,
          kind: ConnectionKind.followers.name,
          label: '${compactCount(person.followersCount, languageCode: locale)} ${t.followers}',
        ),
        _ConnectionStat(
          uid: person.uid,
          kind: ConnectionKind.following.name,
          label: '${compactCount(person.followingCount, languageCode: locale)} ${t.following}',
        ),
      ],
    );
  }
}

class _ConnectionStat extends StatelessWidget {
  const _ConnectionStat({required this.uid, required this.kind, required this.label});

  final String uid;
  final String kind;
  final String label;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.push('/connections/$uid/$kind'),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MetaText(text: label, emphasized: true),
    ),
  );
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.person, required this.isMe});

  final UserProfile person;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    if (isMe) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => context.push('/edit-profile'),
              child: Text(t.editProfile),
            ),
          ),
        ],
      );
    }
    final refTarget = UserProfileRef(
      uid: person.uid,
      displayName: person.displayName,
      photoUrl: person.photoUrl,
    );
    return Row(
      children: [
        Expanded(child: FollowButton(target: person)),
        const SizedBox(width: AppSpacing.m),
        MessageButton(target: refTarget, label: t.message),
      ],
    );
  }
}

/// Blocking is a graph edge like following, and it is reversible from the same
/// place. The menu only offers the direction the current edge allows.
class _BlockMenu extends ConsumerWidget {
  const _BlockMenu({required this.subjectUid});

  final String subjectUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final me = ref.watch(currentUserProvider).valueOrNull;
    if (me == null) return const SizedBox.shrink();
    final blocked = me.blocking.contains(subjectUid);

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz),
      onSelected: (_) => _toggle(context, ref, block: !blocked),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: blocked ? 'unblock' : 'block',
          child: Text(blocked ? t.unblock : t.block),
        ),
      ],
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, {required bool block}) async {
    final messenger = ScaffoldMessenger.of(context);
    final t = context.t;
    final me = ref.read(currentUidProvider);
    if (me == null) return;
    try {
      await ref.read(profileRepositoryProvider).setBlock(
        blockerUid: me,
        blockedUid: subjectUid,
        blocked: block,
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(block ? t.blocked : t.unblock)));
  }
}

class _PostGrid extends StatelessWidget {
  const _PostGrid({required this.posts, required this.columns});

  final List<Post> posts;
  final int columns;

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    padding: EdgeInsets.zero,
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: 1,
      crossAxisSpacing: 1,
    ),
    itemCount: posts.length,
    itemBuilder: (context, index) {
      final post = posts[index];
      final media = post.layoutMedia;
      return InkWell(
        onTap: () => context.push('/feed/post/${post.postId}'),
        child: media.isEmpty
            ? _CaptionCell(post: post)
            : MediaView(media: media.first),
      );
    },
  );
}

/// A text post still occupies a cell, so the grid keeps the author's cadence
/// instead of silently dropping the entries that carry no image.
class _CaptionCell extends StatelessWidget {
  const _CaptionCell({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(AppSpacing.s),
      child: Text(
        post.caption,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface),
      ),
    );
  }
}
