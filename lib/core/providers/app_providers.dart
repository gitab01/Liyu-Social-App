import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liyu_social/core/offline/write_queue.dart';
import 'package:liyu_social/data/local/local_store.dart';
import 'package:liyu_social/data/media/media_store.dart';
import 'package:liyu_social/domain/models/user.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dependency injection for the whole app. Nothing that reads these providers
/// knows whether it is talking to Firebase or to the on-device backend — the
/// implementations are chosen once, in `bootstrap()`.

/// Overridden in `bootstrap()`, after `SharedPreferences.getInstance()`.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw StateError('sharedPreferencesProvider must be overridden at startup'),
);

/// Overridden once the store has been hydrated and seeded.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw StateError('localStoreProvider must be overridden at startup'),
);

final connectionMonitorProvider = Provider<ConnectionMonitor>(
  (ref) => throw StateError('connectionMonitorProvider must be overridden at startup'),
);

final writeQueueProvider = Provider<LocalWriteQueue>(
  (ref) => throw StateError('writeQueueProvider must be overridden at startup'),
);

final mediaStoreProvider = Provider<MediaStore>((ref) => MediaStore());

/// The backend this process started with. Changing it reinitializes the SDK, so
/// the settings screen hands back a restart rather than swapping underneath.
final backendModeProvider = Provider<BackendMode>((ref) => BackendMode.local);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw StateError('authRepositoryProvider must be overridden at startup'),
);

final feedRepositoryProvider = Provider<FeedRepository>(
  (ref) => throw StateError('feedRepositoryProvider must be overridden at startup'),
);

final storyRepositoryProvider = Provider<StoryRepository>(
  (ref) => throw StateError('storyRepositoryProvider must be overridden at startup'),
);

final messagingRepositoryProvider = Provider<MessagingRepository>(
  (ref) => throw StateError('messagingRepositoryProvider must be overridden at startup'),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => throw StateError('profileRepositoryProvider must be overridden at startup'),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => throw StateError('notificationRepositoryProvider must be overridden at startup'),
);

final mediaRepositoryProvider = Provider<MediaRepository>(
  (ref) => throw StateError('mediaRepositoryProvider must be overridden at startup'),
);

/// The signed-in account, or null at the sign-in gate.
final signedInUserProvider = StreamProvider<UserProfile?>(
  (ref) => ref.watch(authRepositoryProvider).authState(),
);

final currentUidProvider = Provider<String?>((ref) => ref.watch(signedInUserProvider).valueOrNull?.uid);

/// Kept live separately from the session, because counts are mutated
/// server-side by counter functions.
final currentUserProvider = StreamProvider<UserProfile?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(profileRepositoryProvider).watch(uid);
});

/// Whether the client currently believes it can reach the backend. The first
/// value is read synchronously so the first frame is not wrong about it.
final connectionStateProvider = StreamProvider<bool>((ref) async* {
  final monitor = ref.watch(connectionMonitorProvider);
  yield monitor.online;
  yield* monitor.changes;
});

final connectionOnlineProvider = Provider<bool>((ref) {
  return ref.watch(connectionStateProvider).valueOrNull ?? ref.watch(connectionMonitorProvider).online;
});

final pendingWritesProvider = Provider<ValueNotifier<int>>(
  (ref) => ref.watch(writeQueueProvider).pendingWrites,
);

final themeModeProvider = StateProvider<ThemeMode>((ref) {
  final stored = ref.read(sharedPreferencesProvider).getString('ui.themeMode');
  return switch (stored) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
});

final localeProvider = StateProvider<Locale>((ref) => Locale(
  ref.read(sharedPreferencesProvider).getString('ui.languageCode') == 'am' ? 'am' : 'en',
));

/// Thumbnails only in lists, and no media prefetch off Wi-Fi.
final dataSaverProvider = StateProvider<bool>(
  (ref) => ref.read(sharedPreferencesProvider).getBool('ui.dataSaver') ?? true,
);

final offlineSimulatedProvider = StateProvider<bool>(
  (ref) => ref.read(sharedPreferencesProvider).getBool('net.simulatedOffline') ?? false,
);
