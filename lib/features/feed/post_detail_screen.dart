import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/providers/feature_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/core/utils/formatters.dart';
import 'package:liyu_social/core/widgets/layout.dart';
import 'package:liyu_social/core/widgets/state_views.dart';
import 'package:liyu_social/core/widgets/user_avatar.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/post.dart';
import 'package:liyu_social/features/feed/widgets/post_tile.dart';

/// One post with its whole thread.
///
/// The post renders at full media quality here because the reader asked for it,
/// while the thread below stays text-first — a comment list is the cheapest part
/// of the app to fetch, and it is the part that keeps updating.
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({required this.postId, super.key});

  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _draft = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _send(Post post) async {
    final text = _draft.text.trim();
    if (text.isEmpty) return;
    final author = _author();
    if (author == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      await ref.read(feedRepositoryProvider).addComment(post: post, author: author, text: text);
      if (!mounted) return;
      _draft.clear();
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  UserProfileRef? _author() {
    final user = ref.read(currentUserProvider).valueOrNull ?? ref.read(signedInUserProvider).valueOrNull;
    if (user == null) return null;
    return UserProfileRef(uid: user.uid, displayName: user.displayName, photoUrl: user.photoUrl);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final post = ref.watch(postProvider(widget.postId));

    return Scaffold(
      appBar: AppBar(title: Text(t.comments), automaticallyImplyLeading: true),
      body: post.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => FailureView(
          error: error,
          onRetry: () => ref.invalidate(postProvider(widget.postId)),
        ),
        data: (found) {
          if (found == null) {
            return EmptyState(
              title: t.postDeleted,
              icon: Icons.delete_outline,
              action: FilledButton(onPressed: () => context.go('/feed'), child: Text(t.home)),
            );
          }
          return Column(
            children: [
              const OfflineBanner(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  children: [
                    PostTile(post: found, showFullMedia: true, onTap: null),
                    _Thread(post: found),
                  ],
                ),
              ),
              _CommentBar(
                enabled: !_sending,
                busy: _sending,
                controller: _draft,
                onSend: () => _send(found),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The thread, oldest first, with its own live stream.
class _Thread extends ConsumerWidget {
  const _Thread({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final text = Theme.of(context).textTheme;
    final comments = ref.watch(commentsProvider(post.postId));
    final locale = Localizations.localeOf(context).languageCode;

    return comments.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: FailureView(error: error),
      ),
      data: (thread) {
        if (thread.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.xl),
            child: Text(t.noPostsYet, style: text.bodyMedium),
          );
        }
        return Column(
          children: [
            SectionHeader(title: '${t.comments} · ${thread.length}'),
            for (final comment in thread)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.s),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UserAvatar(name: comment.authorName, photoUrl: comment.authorPhoto, size: 32),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: GestureDetector(
                                  onTap: () => context.push('/profile/${comment.authorUid}'),
                                  child: Text(
                                    comment.authorName,
                                    style: text.titleSmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.s),
                              MetaText(text: relativeTime(comment.createdAt, locale)),
                            ],
                          ),
                          SelectableText(comment.text, style: text.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Comment input. Kept above the keyboard rather than inside the list, because a
/// thread that shifts while you are typing is the classic small-screen bug.
class _CommentBar extends StatelessWidget {
  const _CommentBar({
    required this.enabled,
    required this.busy,
    required this.controller,
    required this.onSend,
  });

  final bool enabled;
  final bool busy;
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      surfaceTintColor: Colors.transparent,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.s, AppSpacing.m, AppSpacing.s),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: t.writeAComment),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              IconButton.filledTonal(
                onPressed: enabled ? onSend : null,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                tooltip: t.addComment,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
