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
import 'package:liyu_social/domain/models/notification.dart';

/// The notification tray.
///
/// The tray renders the same fan-out a push message carries, so a tap opens the
/// same route the notification would have. The actor and the sentence were
/// written into the document when the event happened, which is why this screen
/// needs no copy of its own about what a like or a follow means.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final uid = ref.watch(currentUidProvider);
    final notifications = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.notifications),
        actions: [
          IconButton(
            tooltip: t.markAllRead,
            icon: const Icon(Icons.done_all),
            onPressed: uid == null
                ? null
                : () => ref.read(notificationRepositoryProvider).markAllRead(uid).catchError((Object _) {}),
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: notifications.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => FailureView(
                error: error,
                onRetry: () => ref.invalidate(notificationsProvider),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyState(title: t.nothingNewHere, icon: Icons.notifications_none);
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SectionDivider(indent: 72),
                  itemBuilder: (context, index) => _NotificationRow(notification: list[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationRow extends ConsumerWidget {
  const _NotificationRow({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).languageCode;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.xs),
      leading: UserAvatar(name: notification.actorName, photoUrl: notification.actorPhoto, size: 40),
      title: Text(
        notification.actorName,
        style: text.bodyMedium?.copyWith(fontWeight: notification.isUnread ? FontWeight.w600 : null),
      ),
      subtitle: Text(
        notification.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: text.bodySmall?.copyWith(color: scheme.onSurface.withValues(alpha: 0.7)),
      ),
      // An unread row carries one flat dot rather than a tinted background, so
      // the list stays on a pure canvas.
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MetaText(text: relativeTime(notification.createdAt, locale)),
          if (notification.isUnread) ...[
            const SizedBox(height: AppSpacing.s),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary),
            ),
          ],
        ],
      ),
      onTap: () {
        // Marking read is fire-and-forget: the row is already leaving the screen.
        ref.read(notificationRepositoryProvider).markRead(notification.id).catchError((Object _) {});
        context.push(notification.deepLink);
      },
    );
  }
}
