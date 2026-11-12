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

/// The inbox: one row per conversation, newest activity first.
///
/// Every field a row needs is denormalized onto the conversation document, so
/// this list is one read rather than one read plus a message fetch per row — the
/// difference that matters on a slow connection. Unread counts are per-participant,
/// so the badge is this reader's, not the thread's.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final uid = ref.watch(currentUidProvider);
    final inbox = ref.watch(inboxProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.messages), automaticallyImplyLeading: false),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: inbox.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => FailureView(
                error: error,
                onRetry: () => ref.invalidate(inboxProvider),
              ),
              data: (conversations) {
                if (conversations.isEmpty) {
                  return EmptyState(
                    title: t.noConversations,
                    detail: t.startChat,
                    icon: Icons.chat_bubble_outline,
                    action: FilledButton(
                      onPressed: () => context.go('/search'),
                      child: Text(t.people),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  itemCount: conversations.length,
                  separatorBuilder: (_, __) => const SectionDivider(indent: 72),
                  itemBuilder: (context, index) =>
                      _ConversationRow(conversation: conversations[index], readerUid: uid ?? ''),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.conversation, required this.readerUid});

  final Conversation conversation;
  final String readerUid;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).languageCode;
    final unread = conversation.unreadFor(readerUid);
    final mine = conversation.lastSenderUid == readerUid;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.xs),
      leading: UserAvatar(name: conversation.peer.displayName, photoUrl: conversation.peer.photoUrl, size: 48),
      title: Text(
        conversation.peer.displayName,
        style: text.titleMedium?.copyWith(fontWeight: unread > 0 ? FontWeight.w700 : null),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        conversation.lastMessage.isEmpty
            ? t.startChat
            : '${mine ? 'You: ' : ''}${conversation.lastMessage}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.bodySmall?.copyWith(color: scheme.onSurface.withValues(alpha: unread > 0 ? 0.9 : 0.65)),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (conversation.lastMessageAt != null)
            MetaText(text: relativeTime(conversation.lastMessageAt!, locale)),
          if (unread > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(999)),
              child: Text(
                '$unread',
                style: text.labelSmall?.copyWith(color: scheme.onPrimary),
              ),
            ),
          ],
        ],
      ),
      onTap: () => context.push('/chat/${conversation.conversationId}'),
    );
  }
}
