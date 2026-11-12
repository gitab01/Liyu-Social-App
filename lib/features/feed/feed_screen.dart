import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/providers/feature_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/core/widgets/state_views.dart';
import 'package:liyu_social/domain/models/post.dart';
import 'package:liyu_social/features/feed/widgets/post_tile.dart';
import 'package:liyu_social/features/feed/widgets/story_rail.dart';
import 'package:liyu_social/features/feed/widgets/suggestion_strip.dart';

/// The feed tab.
///
/// Two sources are stitched together behind [feedProvider]: a bounded live head
/// and cursor pages below it. The list therefore never does an unbounded read,
/// and scrolling to the bottom asks for one page rather than the rest of the
/// collection.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// One page ahead of the bottom, so a slow connection is hidden behind the
  /// rows the reader is still looking at.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.extentAfter > 600) return;
    if (ref.read(feedEndReachedProvider)) return;
    ref.read(olderPostsProvider.notifier).loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final posts = ref.watch(feedProvider);
    final loading = ref.watch(feedIsLoadingProvider);
    final headError = ref.watch(feedHeadProvider).error;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.appName, style: Theme.of(context).textTheme.headlineSmall),
        actions: [
          const PendingWritesPill(),
          _AlertsButton(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: t.settings,
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(feedHeadProvider);
                ref.invalidate(storiesProvider);
              },
              child: CustomScrollView(
                controller: _scroll,
                slivers: [
                  const SliverToBoxAdapter(child: StoryRail()),
                  if (headError != null && posts.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: FailureView(
                        error: headError,
                        onRetry: () => ref.invalidate(feedHeadProvider),
                      ),
                    )
                  else if (posts.isEmpty && loading)
                    const SliverToBoxAdapter(child: _FeedSkeleton())
                  else if (posts.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: Icons.rss_feed_outlined,
                        title: t.noPostsYet,
                        detail: t.suggestionsForYou,
                        action: FilledButton(
                          onPressed: () => context.go('/search'),
                          child: Text(t.search),
                        ),
                      ),
                    )
                  else ...[
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        childCount: posts.length,
                        (context, index) => PostTile(post: posts[index]),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SuggestionStrip()),
                    SliverToBoxAdapter(
                      child: _FeedFooter(
                        loading: loading,
                        endReached: ref.watch(feedEndReachedProvider),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedFooter extends StatelessWidget {
  const _FeedFooter({required this.loading, required this.endReached});

  final bool loading;
  final bool endReached;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    if (loading) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Center(
          child: Text(t.loadingMore, style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }
    if (endReached) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: Text(t.endOfFeed, style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }
    return const SizedBox(height: AppSpacing.xl);
  }
}

/// Three flat placeholder rows. A spinner alone tells the reader nothing about
/// how long to wait; a skeleton gives the list its real shape immediately.
class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Inside a sliver, so no viewport of its own: three rows that match a real
    // post tile is all a skeleton needs.
    return Column(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Bar(width: 42, height: 42, radius: 21, color: scheme.outline),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(child: _Bar(width: 140, height: 12, color: scheme.outline)),
                  ],
                ),
                const SizedBox(height: AppSpacing.m),
                _Bar(width: double.infinity, height: 12, color: scheme.outline),
                const SizedBox(height: AppSpacing.s),
                _Bar(width: 220, height: 12, color: scheme.outline),
              ],
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height, this.radius = 4, required this.color});

  final double width;
  final double height;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
  );
}

/// Count of writes waiting for a connection. Rendered from the queue's own
/// notifier so it updates without polling.
class PendingWritesPill extends ConsumerWidget {
  const PendingWritesPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(pendingWritesProvider);
    return ValueListenableBuilder<int>(
      valueListenable: notifier,
      builder: (context, count, _) {
        if (count == 0) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(right: AppSpacing.s),
          child: Center(
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.secondary),
            ),
          ),
        );
      },
    );
  }
}

class _AlertsButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider);
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: context.t.notifications,
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: unread > 0,
        backgroundColor: scheme.primary,
        textColor: scheme.onPrimary,
        label: Text('$unread'),
        child: const Icon(Icons.notifications_none),
      ),
    );
  }
}

/// A post rendered outside a list (detail view, profile preview).
Widget standalonePost(BuildContext context, Post post) => PostTile(post: post, showFullMedia: true);
