import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liyu_social/app/app.dart';
import 'package:liyu_social/app/bootstrap.dart';
import 'package:liyu_social/app/bootstrap_result_provider.dart';
import 'package:liyu_social/core/offline/write_queue.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/data/local/connection_monitor.dart';
import 'package:liyu_social/data/local/local_backend.dart';
import 'package:liyu_social/data/local/local_social_repositories.dart';
import 'package:liyu_social/data/local/local_store.dart';
import 'package:liyu_social/data/local/seed_content.dart';
import 'package:liyu_social/data/media/media_store.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The on-device backend, opened the same way `bootstrap()` opens it.
///
/// Every test that needs a working app gets one here with no credentials, no
/// emulator and no network — which is the property the local backend exists to
/// provide.
class TestBackend {
  TestBackend._({
    required this.store,
    required this.monitor,
    required this.queue,
    required this.container,
    required this.stories,
  });

  final LocalStore store;
  final InProcessConnectionMonitor monitor;
  final LocalWriteQueue queue;
  final ProviderContainer container;
  final LocalStoryRepository stories;

  static Future<TestBackend> open({bool offline = false}) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await LocalStore.open(prefs);
    await store.seedIfEmpty(localSeedDocuments());

    final monitor = InProcessConnectionMonitor(offline: offline);
    final queue = LocalWriteQueue(monitor: monitor);
    final mediaStore = MediaStore();
    final overrides = localBackendOverrides(
      store: store,
      monitor: monitor,
      queue: queue,
      mediaStore: mediaStore,
    );

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        localStoreProvider.overrideWithValue(store),
        connectionMonitorProvider.overrideWithValue(monitor),
        writeQueueProvider.overrideWithValue(queue),
        bootstrapResultProvider.overrideWithValue(
          const BootstrapResult(overrides: [], backend: BackendMode.local, firebaseFailure: null),
        ),
        ...overrides,
      ],
    );

    return TestBackend._(
      store: store,
      monitor: monitor,
      queue: queue,
      container: container,
      stories: container.read(storyRepositoryProvider) as LocalStoryRepository,
    );
  }

  T repository<T>(Provider<T> provider) => container.read(provider);

  /// The real app, on this container. Pumping this instead of a hand-built
  /// scaffold keeps the router, the redirect and the provider graph under test.
  Widget get app => UncontrolledProviderScope(
    container: container,
    child: const LiyuApp(result: BootstrapResult(overrides: [], backend: BackendMode.local, firebaseFailure: null)),
  );

  /// Signs in as the seeded demo account, through the same OTP path the UI uses.
  Future<String> signInAsDemo() async {
    final auth = repository<AuthRepository>(authRepositoryProvider);
    final challenge = await auth.sendOtp(localDemoPhone());
    final user = await auth.signInWithOtp(challenge: challenge, code: challenge.devCode!);
    return user.uid;
  }

  Future<void> dispose() async {
    stories.dispose();
    container.dispose();
    queue.dispose();
    await monitor.close();
    await store.dispose();
  }
}
