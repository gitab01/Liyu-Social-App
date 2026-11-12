import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/providers/feature_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/core/utils/formatters.dart';
import 'package:liyu_social/core/widgets/media_view.dart';
import 'package:liyu_social/core/widgets/user_avatar.dart';
import 'package:liyu_social/domain/models/story.dart';

/// Full-screen story playback for one author.
///
/// Auto-advance is the default, but a finger held down stops the clock: the
/// reader, not the timer, decides how long a frame is on screen. Views are
/// written as soon as a story becomes the active one, because a story that is
/// skipped after being rendered was still seen.
class StoryViewerScreen extends ConsumerStatefulWidget {
  const StoryViewerScreen({required this.authorUid, super.key});

  final String authorUid;

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(seconds: 6);

  late final AnimationController _clock = AnimationController(vsync: this, duration: _duration);
  int _index = 0;
  final Set<String> _reported = {};
  bool _held = false;

  @override
  void initState() {
    super.initState();
    _clock.addStatusListener((status) {
      if (status == AnimationStatus.completed) _advance(1);
    });
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  List<Story> _stories() {
    final now = DateTime.now();
    final all = ref.read(storiesProvider).valueOrNull ?? const <Story>[];
    final list = all.where((s) => s.authorUid == widget.authorUid && !s.isExpiredAt(now)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  void _startCurrent() {
    final stories = _stories();
    if (stories.isEmpty || _index >= stories.length) return;
    final story = stories[_index];
    if (_reported.add(story.storyId)) {
      final uid = ref.read(currentUidProvider);
      if (uid != null) {
        ref.read(storyRepositoryProvider).markViewed(storyId: story.storyId, uid: uid).catchError((Object _) {});
      }
    }
    _clock
      ..stop()
      ..value = 0;
    if (!_held) _clock.forward();
  }

  void _advance(int delta) {
    final stories = _stories();
    final next = _index + delta;
    if (next < 0 || next >= stories.length) {
      context.pop();
      return;
    }
    setState(() => _index = next);
    _startCurrent();
  }

  void _setHeld(bool value) {
    setState(() => _held = value);
    if (value) {
      _clock.stop();
    } else {
      _clock.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stories = ref.watch(storiesProvider).valueOrNull;
    if (stories == null) {
      return Scaffold(
        backgroundColor: AppPalette.black,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final visible = stories.where((s) => s.authorUid == widget.authorUid && !s.isExpiredAt(DateTime.now())).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (visible.isEmpty) {
      return Scaffold(
        backgroundColor: AppPalette.black,
        body: Center(
          child: TextButton.icon(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.close, color: AppPalette.white),
            label: Text(context.t.storyExpired, style: const TextStyle(color: AppPalette.white)),
          ),
        ),
      );
    }

    if (_index >= visible.length) _index = visible.length - 1;
    final story = visible[_index];
    if (_clock.value == 0 && !_clock.isAnimating && !_held) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startCurrent());
    }

    return Scaffold(
      backgroundColor: AppPalette.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTapDown: (_) => _setHeld(true),
            onTapUp: (_) => _setHeld(false),
            onTapCancel: () => _setHeld(false),
            onLongPressStart: (_) => _setHeld(true),
            onLongPressEnd: (_) => _setHeld(false),
            child: ColoredBox(
              color: AppPalette.black,
              child: Center(child: MediaView(media: story.media, quality: MediaQuality.full, fit: BoxFit.contain)),
            ),
          ),
          // Left and right thirds are the previous/next zones, kept above the
          // image but below the header controls.
          Row(
            children: [
              Expanded(flex: 3, child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => _advance(-1))),
              Expanded(flex: 2, child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => _advance(1))),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _Header(
              story: story,
              index: _index,
              total: visible.length,
              progress: _clock,
              isMine: story.authorUid == ref.watch(currentUidProvider),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Caption(story: story, held: _held),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.story,
    required this.index,
    required this.total,
    required this.progress,
    required this.isMine,
  });

  final Story story;
  final int index;
  final int total;
  final AnimationController progress;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, AppSpacing.m),
        child: Column(
          children: [
            Row(
              children: [
                UserAvatar(name: story.authorName, photoUrl: story.authorPhoto, size: 34),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(story.authorName, style: const TextStyle(color: AppPalette.white, fontWeight: FontWeight.w600)),
                      Text(
                        isMine
                            ? '${t.viewedBy}: ${story.viewerUids.length}'
                            : remainingLabel(story, t),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.close, color: AppPalette.white),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            _SegmentRow(index: index, total: total, progress: progress),
          ],
        ),
      ),
    );
  }

  String remainingLabel(Story story, L10n t) {
    final left = story.remainingAt(DateTime.now());
    if (left.inHours >= 1) return '${left.inHours}h ${t.timeLeft}';
    return '${left.inMinutes}m ${t.timeLeft}';
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({required this.index, required this.total, required this.progress});

  final int index;
  final int total;
  final AnimationController progress;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < total; i++)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == total - 1 ? 0 : 4),
            child: i < index
                ? const _Segment(fraction: 1)
                : (i > index
                    ? const _Segment(fraction: 0)
                    : AnimatedBuilder(
                        animation: progress,
                        builder: (context, _) => _Segment(fraction: progress.value),
                      )),
          ),
        ),
    ],
  );
}

class _Segment extends StatelessWidget {
  const _Segment({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: LinearProgressIndicator(
      value: fraction,
      minHeight: 3,
      backgroundColor: Colors.white24,
      valueColor: const AlwaysStoppedAnimation(AppPalette.white),
    ),
  );
}

class _Caption extends StatelessWidget {
  const _Caption({required this.story, required this.held});

  final Story story;
  final bool held;

  @override
  Widget build(BuildContext context) {
    if (story.caption.isEmpty && !held) return const SizedBox.shrink();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (held)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s),
                child: MetaText(text: clockTime(story.createdAt)),
              ),
            if (story.caption.isNotEmpty)
              Text(
                story.caption,
                style: const TextStyle(color: AppPalette.white, fontSize: 15, height: 1.5),
              ),
          ],
        ),
      ),
    );
  }
}
