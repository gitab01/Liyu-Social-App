import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/data/firebase/fcm_notification_service.dart';
import 'package:liyu_social/data/firebase/firebase_auth_repository.dart';
import 'package:liyu_social/data/firebase/firebase_profile_repository.dart';
import 'package:liyu_social/data/firebase/firebase_storage_service.dart';
import 'package:liyu_social/data/firebase/firestore_feed_repository.dart';
import 'package:liyu_social/data/firebase/firestore_messaging_repository.dart';
import 'package:liyu_social/data/firebase/firestore_notification_repository.dart';
import 'package:liyu_social/data/firebase/firestore_story_repository.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// Wires the Firebase backend without making it a hard compile dependency.
///
/// `flutterfire configure` generates `lib/firebase_options.dart`, which does not
/// exist in a checkout that has never been pointed at a project — and importing
/// it here would break `flutter analyze` for every local-backend build and every
/// widget test. So the options are handed in through [registerFirebaseOptions]
/// from the app entrypoint (the one file allowed to import the generated
/// options), and this module only ever touches the abstract `FirebaseOptions`.

/// A lazy source of the generated `DefaultFirebaseOptions`, supplied by the
/// entrypoint once `firebase_options.dart` exists.
typedef FirebaseOptionsLoader = FirebaseOptions Function();

FirebaseOptionsLoader? _optionsLoader;

/// Call from `main()` before [initializeFirebase], guarded by the generated file:
///
/// ```dart
/// registerFirebaseOptions(() => DefaultFirebaseOptions.currentPlatform);
/// ```
///
/// Leaving it unset is not an error: [initializeFirebase] then falls back to the
/// native config (`google-services.json` / `GoogleService-Info.plist`) on mobile
/// and reports failure on platforms that need explicit options.
void registerFirebaseOptions(FirebaseOptionsLoader loader) => _optionsLoader = loader;

/// Brings Firebase up, returning `false` instead of throwing when it cannot.
///
/// The app treats a `false` here as "run on the local backend", so a missing
/// `firebase_options.dart`, a bad API key, or a cold-start network failure must
/// never crash the process. Every failure path is swallowed deliberately; that
/// is the whole contract of this function.
Future<bool> initializeFirebase() async {
  try {
    if (Firebase.apps.isNotEmpty) return true;
    final loader = _optionsLoader;
    if (loader != null) {
      await Firebase.initializeApp(options: loader());
    } else {
      // No Dart options: on mobile the plugin reads the native config file, and
      // throws everywhere else. Either outcome is handled by the catch below.
      await Firebase.initializeApp();
    }
    return Firebase.apps.isNotEmpty;
  } on Object {
    return false;
  }
}

/// The provider overrides that swap the on-device backend for Firebase.
///
/// Each repository reads its shared dependencies (the write queue, the
/// connection monitor) through `ref`, so a Firebase build still gets the same
/// offline queue and monitor the app started with — only the storage layer
/// changes. Override the whole set in one `ProviderScope`:
///
/// ```dart
/// ProviderScope(overrides: [...bootstrapOverrides, ...firebaseOverrides()])
/// ```
List<Override> firebaseOverrides() {
  return [
    backendModeProvider.overrideWithValue(BackendMode.firebase),
    authRepositoryProvider.overrideWith((ref) => FirebaseAuthRepository()),
    feedRepositoryProvider.overrideWith((ref) => FirestoreFeedRepository()),
    storyRepositoryProvider.overrideWith((ref) => FirestoreStoryRepository()),
    messagingRepositoryProvider.overrideWith((ref) => FirestoreMessagingRepository()),
    profileRepositoryProvider.overrideWith((ref) => FirebaseProfileRepository()),
    notificationRepositoryProvider.overrideWith((ref) => FirestoreNotificationRepository()),
    mediaRepositoryProvider.overrideWith(
      (ref) => FirebaseMediaService(writeQueue: ref.watch(writeQueueProvider)),
    ),
  ];
}

/// Convenience override exposing a single [FcmNotificationService] instance to
/// the widget tree so a tap can be forwarded to the router. The entrypoint owns
/// the instance and calls `startPush`; the provider only hands it back to UI.
final fcmServiceProvider = Provider<FcmNotificationService>((ref) => FcmNotificationService());
