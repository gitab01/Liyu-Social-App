import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/features/auth/sign_in_screen.dart';
import 'package:liyu_social/features/chat/inbox_screen.dart';
import 'package:liyu_social/features/chat/thread_screen.dart';
import 'package:liyu_social/features/composer/composer_screen.dart';
import 'package:liyu_social/features/feed/feed_screen.dart';
import 'package:liyu_social/features/feed/post_detail_screen.dart';
import 'package:liyu_social/features/notifications/notifications_screen.dart';
import 'package:liyu_social/features/profile/connections_screen.dart';
import 'package:liyu_social/features/profile/edit_profile_screen.dart';
import 'package:liyu_social/features/profile/profile_screen.dart';
import 'package:liyu_social/features/search/search_screen.dart';
import 'package:liyu_social/features/settings/settings_screen.dart';
import 'package:liyu_social/features/shell/app_shell.dart';
import 'package:liyu_social/features/stories/story_viewer_screen.dart';

/// Route map, and the only place that decides where a session is allowed to be.
///
/// The redirect reads the same auth stream as everything else, so a token that
/// expires mid-session pulls the UI back to the gate without any screen having
/// to ask. `refreshListenable` is what makes that happen: a `GoRouter` only
/// re-evaluates a redirect when it is told the inputs moved.
final _authRefreshProvider = Provider<ValueNotifier<int>>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(currentUidProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);
  return refresh;
});

/// Push taps and in-app links both arrive here; the router consumes and clears.
final deepLinkProvider = Provider<ValueNotifier<String?>>((ref) {
  final link = ValueNotifier<String?>(null);
  ref.onDispose(link.dispose);
  return link;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/feed',
    refreshListenable: ref.watch(_authRefreshProvider),
    redirect: (context, state) {
      final auth = ref.read(signedInUserProvider);
      final uid = ref.read(currentUidProvider);
      final onGate = state.matchedLocation == '/sign-in';

      // The first auth emission has not landed yet: holding position beats
      // bouncing to the gate and back, which would rebuild the shell.
      if (auth.isLoading && uid == null) return onGate ? null : '/sign-in';
      if (uid == null) return onGate ? null : '/sign-in';
      return onGate ? '/feed' : null;
    },
    routes: [
      GoRoute(path: '/sign-in', builder: (context, state) => const SignInScreen()),
      GoRoute(
        path: '/chat/:conversationId',
        builder: (context, state) =>
            ThreadScreen(conversationId: state.pathParameters['conversationId']!),
      ),
      GoRoute(
        path: '/feed/post/:postId',
        builder: (context, state) => PostDetailScreen(postId: state.pathParameters['postId']!),
      ),
      // Stories cover the shell without pushing it, so the rail keeps its place.
      GoRoute(
        path: '/stories/:authorUid',
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: StoryViewerScreen(authorUid: state.pathParameters['authorUid']!),
        ),
      ),
      GoRoute(path: '/notifications', builder: (context, state) => const NotificationsScreen()),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      GoRoute(path: '/edit-profile', builder: (context, state) => const EditProfileScreen()),
      GoRoute(
        path: '/connections/:uid/:kind',
        builder: (context, state) => ConnectionsScreen(
          uid: state.pathParameters['uid']!,
          kind: state.pathParameters['kind']!,
        ),
      ),
      GoRoute(
        path: '/profile/:uid',
        builder: (context, state) => ProfileScreen(uid: state.pathParameters['uid']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(shell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/feed', builder: (context, state) => const FeedScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/search', builder: (context, state) => const SearchScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/create', builder: (context, state) => const ComposerScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/chats', builder: (context, state) => const InboxScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen.self()),
          ]),
        ],
      ),
    ],
  );

  final link = ref.watch(deepLinkProvider);
  void followDeepLink() {
    final target = link.value;
    if (target == null) return;
    link.value = null;
    // A push can arrive before the session resolves; pushing anyway is safe
    // because the redirect runs again and lands on the same route.
    router.push(target);
  }

  link.addListener(followDeepLink);
  ref.onDispose(() => link.removeListener(followDeepLink));
  return router;
});

/// Read once from `MaterialApp.router`; the router instance itself is stable so
/// a theme or language change never resets navigation.
GoRouter createRouter(WidgetRef ref) => ref.watch(appRouterProvider);
