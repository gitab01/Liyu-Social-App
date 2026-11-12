import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/providers/feature_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/core/utils/media_picker.dart';
import 'package:liyu_social/core/widgets/user_avatar.dart';
import 'package:liyu_social/domain/models/story.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';
import 'package:liyu_social/features/composer/application/composer_controller.dart';

/// Stories strip above the feed.
///
/// The first slot is always your own, because publishing is the action most
/// likely to be wanted and least likely to be found elsewhere. The ring is the
/// only state shown: unseen is the accent, seen is the hairline — no badges,
/// no counts, nothing that costs an extra read.
class StoryRail extends ConsumerWidget {
  const StoryRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(storyGroupsProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;
    if (me == null) return const SizedBox.shrink();

    final others = groups.where((g) => g.authorUid != me.uid).toList();
    final mine = groups.where((g) => g.authorUid == me.uid).toList();

    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
        children: [
          _YourStorySlot(
            name: me.displayName,
            photoUrl: me.photoUrl,
            hasStory: mine.isNotEmpty,
          ),
          for (final group in others)
            _StorySlot(group: group, me: me.uid, label: group.authorName),
        ],
      ),
    );
  }
}

class _StorySlot extends StatelessWidget {
  const _StorySlot({required this.group, required this.me, required this.label});

  final StoryGroup group;
  final String me;
  final String label;

  @override
  Widget build(BuildContext context) {
    final first = group.stories.first;
    return SizedBox(
      width: 74,
      child: InkWell(
        onTap: () => context.push('/stories/${group.authorUid}'),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            UserAvatar(
              name: group.authorName,
              photoUrl: first.authorPhoto,
              size: 54,
              storyRing: group.unseenBy(me),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _YourStorySlot extends ConsumerStatefulWidget {
  const _YourStorySlot({required this.name, required this.photoUrl, required this.hasStory});

  final String name;
  final String? photoUrl;
  final bool hasStory;

  @override
  ConsumerState<_YourStorySlot> createState() => _YourStorySlotState();
}

class _YourStorySlotState extends ConsumerState<_YourStorySlot> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return SizedBox(
      width: 74,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy ? null : _add,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                UserAvatar(
                  name: widget.name,
                  photoUrl: widget.photoUrl,
                  size: 54,
                  storyRing: widget.hasStory ? true : null,
                ),
                if (!widget.hasStory)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.primary,
                        border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.add, size: 14, color: Theme.of(context).colorScheme.onPrimary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              widget.hasStory ? t.yourStory : t.newStory,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add() async {
    final messenger = ScaffoldMessenger.of(context);
    final t = context.t;
    setState(() => _busy = true);
    try {
      final files = await pickGalleryImages(maxItems: 1);
      if (files.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final queued = await publishStoryFile(ref, files.first);
      if (!mounted) return;
      setState(() => _busy = false);
      if (queued) {
        messenger.showSnackBar(SnackBar(content: Text(t.queuedForSync)));
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

/// Runs one picked file through compress → upload → story document.
///
/// Shared with the composer's story tab so a story costs exactly what the rail
/// implies it costs, and offline behaviour is identical from either entry point.
/// Returns true when the write was queued rather than delivered, which the
/// caller turns into the honest "will publish when you reconnect" message.
Future<bool> publishStoryFile(WidgetRef ref, SourceFile file, {String caption = ''}) async {
  await ref.read(composerProvider.notifier).publishStory(file, caption: caption);
  return ref.read(pendingWritesProvider).value > 0;
}
