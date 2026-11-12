import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/feature_providers.dart';

/// Tab chrome around the five first-class destinations.
///
/// Badges read the live inbox and tray providers rather than a counter service,
/// which is one less number that can drift from what is actually unread. Tapping
/// the current tab pops it — the standard escape hatch out of a deep thread.
class AppShell extends ConsumerWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  static const _paths = ['/feed', '/search', '/create', '/chats', '/profile'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadChats = ref.watch(inboxUnreadProvider);
    final unreadAlerts = ref.watch(unreadNotificationsProvider);
    final t = context.t;

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        onDestinationSelected: (index) {
          if (index == shell.currentIndex) {
            context.go(_paths[index]);
            return;
          }
          shell.goBranch(index, initialLocation: index == shell.currentIndex);
        },
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: t.home),
          NavigationDestination(icon: const Icon(Icons.search_outlined), selectedIcon: const Icon(Icons.search), label: t.search),
          NavigationDestination(
            icon: const Icon(Icons.add_box_outlined),
            selectedIcon: const Icon(Icons.add_box),
            label: t.create,
          ),
          NavigationDestination(
            icon: _Badge(count: unreadChats, child: const Icon(Icons.chat_bubble_outline)),
            selectedIcon: _Badge(count: unreadChats, child: const Icon(Icons.chat_bubble)),
            label: t.inbox,
          ),
          NavigationDestination(
            icon: _Badge(count: unreadAlerts, child: const Icon(Icons.person_outline)),
            selectedIcon: _Badge(count: unreadAlerts, child: const Icon(Icons.person)),
            label: t.profile,
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    final scheme = Theme.of(context).colorScheme;
    return Badge.count(
      count: count,
      backgroundColor: scheme.primary,
      textColor: scheme.onPrimary,
      // Flat and small: this sits on a tab bar, not on an app icon.
      textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onPrimary),
      child: child,
    );
  }
}
