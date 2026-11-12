import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/providers/feature_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/core/utils/formatters.dart';
import 'package:liyu_social/core/utils/media_picker.dart';
import 'package:liyu_social/core/widgets/media_view.dart';
import 'package:liyu_social/core/widgets/state_views.dart';
import 'package:liyu_social/core/widgets/user_avatar.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/media.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// A direct-message thread.
///
/// Sending is optimistic and the status is the truth: a bubble says *pending*
/// while the write is in flight, *failed* with a retry control when it was
/// refused, and only reads *sent* once the document landed. That is affordable
/// because the message id is minted here before the first attempt, so a retry
/// rewrites the same document instead of leaving a second copy behind.
class ThreadScreen extends ConsumerStatefulWidget {
  const ThreadScreen({required this.conversationId, super.key});

  final String conversationId;

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  static const Uuid _uuid = Uuid();

  final _draft = TextEditingController();
  final _scroll = ScrollController();
  int _readUpTo = -1;

  @override
  void dispose() {
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String? get _uid => ref.read(currentUidProvider);

  Conversation? get _peer {
    for (final conversation in ref.read(inboxProvider).valueOrNull ?? const <Conversation>[]) {
      if (conversation.conversationId == widget.conversationId) return conversation;
    }
    return null;
  }

  Future<void> _send({String text = '', MediaRef? media}) async {
    final uid = _uid;
    final conversation = _peer;
    if (uid == null || conversation == null) return;
    final body = text.trim();
    if (body.isEmpty && media == null) return;

    final message = Message(
      messageId: _uuid.v4(),
      conversationId: widget.conversationId,
      senderUid: uid,
      recipientUid: conversation.peer.uid,
      text: body,
      media: media,
      status: MessageStatus.pending,
      createdAt: DateTime.now(),
    );

    _draft.clear();
    // The stream owns the bubble's status; the pending write it leaves behind is
    // what the thread renders while this call is still in flight.
    await ref.read(messagingRepositoryProvider).send(message);
    _jumpToLatest();
  }

  Future<void> _attach() async {
    final messenger = ScaffoldMessenger.of(context);
    final t = context.t;
    final uid = _uid;
    if (uid == null) return;
    final files = await pickGalleryImages(maxItems: 1);
    if (files.isEmpty) return;

    try {
      final media = ref.read(mediaRepositoryProvider);
      final prepared = await media.prepare(files.first);
      final uploaded = await media.upload(
        ownerUid: uid,
        prepared: prepared,
        purpose: MediaPurpose.chat,
      );
      await _send(media: uploaded);
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('${t.failedToSend}: $error')));
    }
  }

  void _jumpToLatest() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  /// Opening the thread is the read receipt: unreads clear on entry, and only
  /// when the message count actually moved.
  void _clearUnread(int count) {
    final uid = _uid;
    if (uid == null || count == 0 || count == _readUpTo) return;
    _readUpTo = count;
    ref.read(messagingRepositoryProvider).markRead(conversationId: widget.conversationId, uid: uid).catchError((
      Object _,
    ) {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final uid = _uid;
    final messages = ref.watch(threadProvider(widget.conversationId));
    Conversation? conversation;
    for (final c in ref.watch(inboxProvider).valueOrNull ?? const <Conversation>[]) {
      if (c.conversationId == widget.conversationId) {
        conversation = c;
        break;
      }
    }

    final thread = messages.valueOrNull ?? const <Message>[];
    _clearUnread(thread.length);

    return Scaffold(
      appBar: AppBar(
        title: conversation == null
            ? Text(t.messages)
            : Row(
                children: [
                  UserAvatar(name: conversation.peer.displayName, photoUrl: conversation.peer.photoUrl, size: 32),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Text(conversation.peer.displayName, style: Theme.of(context).textTheme.titleMedium),
                  ),
                ],
              ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => FailureView(
                error: error,
                onRetry: () => ref.invalidate(threadProvider(widget.conversationId)),
              ),
              data: (thread) {
                if (thread.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: EmptyState(title: t.startChat, icon: Icons.forum_outlined),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.m, AppSpacing.l, AppSpacing.m),
                  itemCount: thread.length,
                  itemBuilder: (context, index) => _Bubble(
                    message: thread[index],
                    mine: uid != null && thread[index].senderUid == uid,
                    showTime: index == 0 ||
                        thread[index].createdAt.difference(thread[index - 1].createdAt).inMinutes > 20,
                  ),
                );
              },
            ),
          ),
          _ComposerBar(
            controller: _draft,
            onSend: () => _send(text: _draft.text),
            onAttach: _attach,
          ),
        ],
      ),
    );
  }
}

/// One message and, when it is mine, its delivery state.
class _Bubble extends ConsumerWidget {
  const _Bubble({required this.message, required this.mine, required this.showTime});

  final Message message;
  final bool mine;
  final bool showTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: showTime ? AppSpacing.s : AppSpacing.xs),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showTime)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: MetaText(text: clockTime(message.createdAt)),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s),
              decoration: BoxDecoration(
                // Flat fill, no shadow: the two tones are enough to tell the
                // sides apart, and they hold up in the dark theme unchanged.
                color: mine ? scheme.primary : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(mine ? 14 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.hasMedia)
                    Padding(
                      padding: EdgeInsets.only(bottom: message.text.isEmpty ? 0 : AppSpacing.s),
                      child: SizedBox(
                        width: 180,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: AspectRatio(
                            aspectRatio: message.media!.aspectRatio.clamp(0.7, 1.8),
                            child: MediaView(media: message.media!, quality: MediaQuality.thumbnail),
                          ),
                        ),
                      ),
                    ),
                  if (message.text.isNotEmpty)
                    Text(
                      message.text,
                      style: text.bodyMedium?.copyWith(color: mine ? scheme.onPrimary : scheme.onSurface),
                    ),
                ],
              ),
            ),
          ),
          // Only my own outgoing messages carry a state; an incoming one is
          // simply there, and a delivered tick for it would be invented.
          if (mine) _StatusLine(message: message),
          if (mine && message.status == MessageStatus.failed)
            TextButton.icon(
              onPressed: () =>
                  ref.read(messagingRepositoryProvider).retry(message).catchError((Object _) => message),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(t.retry),
              style: TextButton.styleFrom(
                foregroundColor: scheme.error,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
    );
  }
}

/// The one-word delivery label under an outgoing bubble.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    if (message.status == MessageStatus.pending) {
      return MetaText(text: t.pending);
    }
    if (message.status == MessageStatus.failed) {
      return Text(
        message.error == null ? t.failedToSend : '${t.failedToSend} — ${message.error}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
      );
    }
    return MetaText(text: t.sent);
  }
}

/// Message input: text, one-tap photo, and send.
class _ComposerBar extends StatelessWidget {
  const _ComposerBar({required this.controller, required this.onSend, required this.onAttach});

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.s, AppSpacing.m, AppSpacing.s),
          child: Row(
            children: [
              IconButton(onPressed: onAttach, icon: const Icon(Icons.image_outlined), tooltip: t.addPhoto),
              Expanded(
                child: TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: t.typeAMessage),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              IconButton.filled(onPressed: onSend, icon: const Icon(Icons.send), tooltip: t.send),
            ],
          ),
        ),
      ),
    );
  }
}
