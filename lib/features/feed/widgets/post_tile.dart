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
import 'package:liyu_social/core/widgets/user_avatar.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/media.dart';
import 'package:liyu_social/domain/models/post.dart';
import 'package:liyu_social/features/feed/widgets/post_actions.dart';

/// One feed row.
///
/// It reads its own reaction state through a per-post stream instead of taking
/// it as a parameter, so liking a post rebuilds one tile rather than the whole
/// list — the difference between a smooth scroll and a stutter on a mid-range
/// handset.
class PostTile extends ConsumerWidget {
  const PostTile({
    required this.post,
    this.showFullMedia = false,
    this.onTap,
    super.key,
  });

  final Post post;
  final bool showFullMedia;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).languageCode;
    final myReaction = ref.watch(myReactionProvider(post.postId)).valueOrNull;
    final dataSaver = ref.watch(dataSaverProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.m, AppSpacing.s, 0),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => context.push('/profile/${post.authorUid}'),
                child: UserAvatar(name: post.authorName, photoUrl: post.authorPhoto, size: 42),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.authorName, style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Row(
                      children: [
                        Flexible(
                          child: MetaText(text: relativeTime(post.createdAt, locale)),
                        ),
                        if (post.audience == Audience.followers) ...[
                          const SizedBox(width: AppSpacing.s),
                          Icon(Icons.lock_outline, size: 12, color: scheme.onSurface.withValues(alpha: 0.5)),
                          const SizedBox(width: 3),
                          Flexible(child: MetaText(text: t.followersOnly)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              PostOverflowMenu(post: post),
            ],
          ),
        ),
        if (post.caption.isNotEmpty)
          GestureDetector(
            onTap: onTap ?? () => context.push('/feed/post/${post.postId}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, 0),
              child: Text(post.caption, style: text.bodyLarge),
            ),
          ),
        if (post.layoutMedia.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.m),
          MediaStrip(
            media: post.layoutMedia,
            quality: showFullMedia || !dataSaver ? MediaQuality.full : MediaQuality.thumbnail,
            onTap: onTap ?? () => context.push('/feed/post/${post.postId}'),
          ),
        ],
        PostActionRow(
          post: post,
          reactCount: post.likesCount,
          liked: myReaction != null,
          reactionEmoji: myReaction,
        ),
        const SizedBox(height: AppSpacing.xs),
        SectionDivider(),
      ],
    );
  }
}

/// Media block that reserves its height from the stored aspect ratio, so a row
/// never jumps when pixels arrive.
class MediaStrip extends StatelessWidget {
  const MediaStrip({required this.media, required this.quality, this.onTap, super.key});

  final List<MediaRef> media;
  final MediaQuality quality;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (media.length == 1) {
      final ratio = media.first.aspectRatio.clamp(0.6, 2.2);
      return GestureDetector(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: ratio,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: MediaView(media: media.first, quality: quality),
          ),
        ),
      );
    }

    final shown = media.take(4).toList();
    final extra = media.length - shown.length;
    final columns = shown.length == 2 ? 2 : (shown.length == 4 ? 2 : 3);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      child: GestureDetector(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = 4.0;
            final tileWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in shown)
                    SizedBox(
                      width: tileWidth,
                      height: tileWidth,
                      child: _TileOverlay(
                        media: item,
                        quality: quality,
                        trailingLabel: extra > 0 && item == shown.last ? '+$extra' : null,
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TileOverlay extends StatelessWidget {
  const _TileOverlay({required this.media, required this.quality, this.trailingLabel});

  final MediaRef media;
  final MediaQuality quality;
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final image = MediaView(media: media, quality: quality);
    if (trailingLabel == null) return ClipRect(child: image);
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(child: image),
        // Flat scrim on one tile only, so the label stays legible without
        // tinting the whole strip.
        ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
        Center(child: Text(trailingLabel!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
      ],
    );
  }
}

/// Shared row of reaction + comment + share controls.
class PostActionRow extends ConsumerWidget {
  const PostActionRow({
    required this.post,
    required this.reactCount,
    required this.liked,
    this.reactionEmoji,
    this.compact = false,
    super.key,
  });

  final Post post;
  final int reactCount;
  final bool liked;
  final String? reactionEmoji;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).languageCode;
    final uid = ref.watch(currentUidProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: uid == null
                ? null
                : () => ref
                    .read(feedRepositoryProvider)
                    .toggleReaction(postId: post.postId, uid: uid)
                    .catchError((Object _) => null),
            icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? scheme.error : scheme.onSurface),
            tooltip: liked ? t.liked : t.like,
          ),
          MetaText(text: compactCount(reactCount, languageCode: locale)),
          const SizedBox(width: AppSpacing.l),
          IconButton(
            onPressed: () => context.push('/feed/post/${post.postId}'),
            icon: const Icon(Icons.mode_comment_outlined),
            tooltip: t.comments,
          ),
          MetaText(text: compactCount(post.commentsCount, languageCode: locale)),
          const Spacer(),
          IconButton(
            onPressed: () => showShareSheet(context, ref, post),
            icon: const Icon(Icons.share_outlined),
            tooltip: t.reply,
          ),
        ],
      ),
    );
  }
}
