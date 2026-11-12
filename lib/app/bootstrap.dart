import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liyu_social/core/offline/write_queue.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/data/firebase/firebase_bootstrap.dart';
import 'package:liyu_social/data/local/connection_monitor.dart';
import 'package:liyu_social/data/local/local_backend.dart';
import 'package:liyu_social/data/local/local_store.dart';
import 'package:liyu_social/data/local/seed_content.dart';
import 'package:liyu_social/data/media/media_store.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the app started with, so the settings screen can explain itself instead
/// of guessing.
class BootstrapResult {
  const BootstrapResult({required this.overrides, required this.backend, required this.firebaseFailure});

  final List<Override> overrides;
  final BackendMode backend;
  final String? firebaseFailure;
}

/// Chooses and wires the backend before the first frame.
///
/// Firebase is preferred when a generated `firebase_options.dart` actually
/// initializes. If it cannot — the usual case on a fresh clone, before
/// `flutterfire configure` has been run — the app falls back to the local
/// backend rather than dying at startup, and remembers that it did so the
/// settings screen can say why.
Future<BootstrapResult> bootstrap() async {
  final prefs = await SharedPreferences.getInstance();

  final store = await LocalStore.open(prefs);
  await store.seedIfEmpty(localSeedDocuments());

  final monitor = InProcessConnectionMonitor(
    offline: prefs.getBool('net.simulatedOffline') ?? false,
  );
  final queue = LocalWriteQueue(monitor: monitor);
  final mediaStore = MediaStore();

  BackendMode mode = BackendMode.local;
  String? firebaseFailure;

  if (prefs.getBool('ui.preferFirebase') ?? false) {
    if (await initializeFirebase()) {
      mode = BackendMode.firebase;
    } else {
      firebaseFailure =
          'Firebase could not start, so this run is on the on-device backend. '
          'Run `flutterfire configure` and rebuild to switch.';
      await prefs.setBool('ui.preferFirebase', false);
      debugPrint('Firebase unavailable, starting on the local backend.');
    }
  }

  final overrides = <Override>[
    sharedPreferencesProvider.overrideWithValue(prefs),
    localStoreProvider.overrideWithValue(store),
    connectionMonitorProvider.overrideWithValue(monitor),
    writeQueueProvider.overrideWithValue(queue),
  ];

  if (mode == BackendMode.firebase) {
    overrides.addAll(firebaseOverrides());
  } else {
    overrides.addAll(localBackendOverrides(store: store, monitor: monitor, queue: queue, mediaStore: mediaStore));
  }

  return BootstrapResult(overrides: overrides, backend: mode, firebaseFailure: firebaseFailure);
}
