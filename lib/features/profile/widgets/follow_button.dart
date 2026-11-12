import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/providers/feature_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/core/utils/formatters.dart';
import 'package:liyu_social/core/widgets/user_avatar.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/user.dart';

/// Follow / Following, driven by the same edge stream the backend enforces.
///
/// It reflects state rather than intent: the label changes when the write has
/// landed, because a follow that has not reached the server is not yet a
/// follow. Offline, the write queue accepts the edge and the stream picks it up
/// when it flushes.
class FollowButton extends ConsumerWidget {
  const FollowButton({required this.target, this.compact = false, super.key});

  final UserProfile target;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final me = ref.watch(currentUidProvider);
    if (me == null || me == target.uid) return const SizedBox.shrink();

    final following = ref.watch(followingStateProvider(target.uid)).valueOrNull ?? false;

    return SizedBox(
      width: compact ? 96 : null,
      child: following
          ? OutlinedButton(
              onPressed: () => _set(ref, me, target.uid, false),
              child: Text(t.followingShort),
            )
          : FilledButton(
              onPressed: () => _set(ref, me, target.uid, true),
              child: Text(t.follow),
            ),
    );
  }

  Future<void> _set(WidgetRef ref, String me, String target, bool following) =>
      ref
          .read(profileRepositoryProvider)
          .setFollow(followerUid: me, targetUid: target, following: following)
          .catchError((Object _) {});
}

/// One person in a list: avatar, name, handle-ish meta, and the actions that
/// make sense from a discovery surface.
class PersonTile extends ConsumerWidget {
  const PersonTile({required this.person, this.showFollow = true, this.trailing, super.key});

  final UserProfile person;
  final bool showFollow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final t = context.t;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.xs),
      leading: GestureDetector(
        onTap: () => context.push('/profile/${person.uid}'),
        child: UserAvatar(name: person.displayName, photoUrl: person.photoUrl, size: 44),
      ),
      title: GestureDetector(
        onTap: () => context.push('/profile/${person.uid}'),
        child: Text(person.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium),
      ),
      subtitle: Text(
        person.bio.trim().isEmpty
            ? '${compactCount(person.followersCount, languageCode: Localizations.localeOf(context).languageCode)} ${t.followers}'
            : person.bio,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing ??
          (showFollow
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MessageButton(target: UserProfileRef(uid: person.uid, displayName: person.displayName, photoUrl: person.photoUrl)),
                    const SizedBox(width: AppSpacing.s),
                    FollowButton(target: person, compact: true),
                  ],
                )
              : null),
    );
  }
}

/// Opens (or reuses) a conversation with someone and goes to the thread.
class MessageButton extends ConsumerStatefulWidget {
  const MessageButton({required this.target, this.label, super.key});

  final UserProfileRef target;
  final String? label;

  @override
  ConsumerState<MessageButton> createState() => _MessageButtonState();
}

class _MessageButtonState extends ConsumerState<MessageButton> {
  bool _busy = false;

  Future<void> _open() async {
    final me = ref.read(currentUidProvider);
    if (me == null) return;
    setState(() => _busy = true);
    try {
      final conversationId = await ref
          .read(messagingRepositoryProvider)
          .openConversationWith(myUid: me, peer: widget.target);
      if (!mounted) return;
      setState(() => _busy = false);
      context.push('/chat/$conversationId');
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    if (label == null) {
      return IconButton(
        onPressed: _busy ? null : _open,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.mail_outline),
        tooltip: context.t.message,
      );
    }
    return OutlinedButton(
      onPressed: _busy ? null : _open,
      child: Text(label),
    );
  }
}
