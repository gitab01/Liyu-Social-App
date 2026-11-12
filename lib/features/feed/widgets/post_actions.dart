import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/providers/feature_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/core/widgets/user_avatar.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/post.dart';
import 'package:uuid/uuid.dart';

/// Row menu: the author can delete, a reader can block.
///
/// There is no "report" that goes nowhere — an unmoderated report button is
/// worse than none, so the reader-facing option is the one the rules actually
/// enforce: blocking, which removes the author's posts from this feed at read
/// time.
class PostOverflowMenu extends ConsumerWidget {
  const PostOverflowMenu({required this.post, super.key});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final uid = ref.watch(currentUidProvider);
    final mine = uid == post.authorUid;

    return PopupMenuButton<String>(
      tooltip: t.report,
      icon: const Icon(Icons.more_horiz),
      onSelected: (value) async {
        switch (value) {
          case 'delete':
            await ref.read(feedRepositoryProvider).deletePost(post.postId).catchError((Object _) {});
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.postDeleted)));
            }
          case 'block':
            await ref
                .read(profileRepositoryProvider)
                .setBlock(blockerUid: uid!, blockedUid: post.authorUid, blocked: true)
                .catchError((Object _) {});
          case 'unblock':
            await ref
                .read(profileRepositoryProvider)
                .setBlock(blockerUid: uid!, blockedUid: post.authorUid, blocked: false)
                .catchError((Object _) {});
        }
      },
      itemBuilder: (context) => [
        if (mine)
          PopupMenuItem(value: 'delete', child: Text(t.delete))
        else if (uid != null) ...[
          PopupMenuItem(value: 'block', child: Text('${t.block} ${post.authorName}')),
          PopupMenuItem(value: 'unblock', child: Text('${t.unblock} ${post.authorName}')),
        ],
      ],
    );
  }
}

/// Sharing in this app means sending the post into a conversation, because that
/// is what metered users actually do — a link pasted into a browser costs data
/// twice.
Future<void> showShareSheet(BuildContext context, WidgetRef ref, Post post) async {
  final t = context.t;
  final uid = ref.read(currentUidProvider);
  if (uid == null) return;

  final conversations = ref.read(inboxProvider).valueOrNull ?? const <Conversation>[];
  final link = 'liyu://feed/post/${post.postId}';

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, AppSpacing.m),
            child: Text(t.share, style: Theme.of(sheetContext).textTheme.titleMedium),
          ),
          if (conversations.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, AppSpacing.m),
              child: Text(t.noConversations, style: Theme.of(sheetContext).textTheme.bodySmall),
            )
          else
            SizedBox(
              height: 200,
              child: ListView.separated(
                itemCount: conversations.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
                itemBuilder: (_, index) {
                  final conversation = conversations[index];
                  return ListTile(
                    leading: UserAvatar(name: conversation.peer.displayName, photoUrl: conversation.peer.photoUrl, size: 40),
                    title: Text(conversation.peer.displayName),
                    trailing: const Icon(Icons.send_outlined),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await sendPostToChat(ref, conversation: conversation, myUid: uid, post: post, link: link);
                      if (context.mounted) {
                        context.push('/chat/${conversation.conversationId}');
                      }
                    },
                  );
                },
              ),
            ),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (sheetContext.mounted) Navigator.pop(sheetContext);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(link)));
              }
            },
            icon: const Icon(Icons.link),
            label: Text(t.copyLink),
          ),
          const SizedBox(height: AppSpacing.s),
        ],
      ),
    ),
  );
}

Future<void> sendPostToChat(
  WidgetRef ref, {
  required Conversation conversation,
  required String myUid,
  required Post post,
  required String link,
}) async {
  final message = Message(
    messageId: Uuid().v4(),
    conversationId: conversation.conversationId,
    senderUid: myUid,
    recipientUid: conversation.peer.uid,
    text: link,
    status: MessageStatus.pending,
    createdAt: DateTime.now(),
  );
  await ref.read(messagingRepositoryProvider).send(message).catchError((Object _) => message);
}
