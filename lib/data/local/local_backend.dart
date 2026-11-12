import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liyu_social/core/offline/write_queue.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/data/local/local_auth_repository.dart';
import 'package:liyu_social/data/local/local_counters.dart';
import 'package:liyu_social/data/local/local_media_service.dart';
import 'package:liyu_social/data/local/local_messaging_repository.dart';
import 'package:liyu_social/data/local/local_queries.dart';
import 'package:liyu_social/data/local/local_social_repositories.dart';
import 'package:liyu_social/data/local/local_store.dart';
import 'package:liyu_social/data/media/media_store.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// Wires the credential-free backend into the provider graph.
///
/// `bootstrap()` calls this when Firebase is not configured, which is the
/// default on a fresh clone: the app is fully usable — sign in, post, chat,
/// expire stories — with nothing but `flutter run`.
List<Override> localBackendOverrides({
  required LocalStore store,
  required ConnectionMonitor monitor,
  required LocalWriteQueue queue,
  required MediaStore mediaStore,
}) {
  final queries = LocalQueries(store);
  final counters = LocalCounters(store);
  final media = LocalMediaService(mediaStore: mediaStore, queue: queue);

  return [
    backendModeProvider.overrideWithValue(BackendMode.local),
    authRepositoryProvider.overrideWithValue(LocalAuthRepository(store)),
    feedRepositoryProvider.overrideWithValue(
      LocalFeedRepository(store: store, queries: queries, counters: counters, queue: queue),
    ),
    // Built lazily and cancelled on dispose: the sweeper is a periodic timer, so
    // it must exist only while something is actually watching stories.
    storyRepositoryProvider.overrideWith((ref) {
      final repository = LocalStoryRepository(
        store: store,
        queries: queries,
        queue: queue,
        deleteMedia: media.delete,
      );
      ref.onDispose(repository.dispose);
      return repository;
    }),
    messagingRepositoryProvider.overrideWithValue(
      LocalMessagingRepository(store: store, queries: queries, counters: counters, queue: queue, monitor: monitor),
    ),
    profileRepositoryProvider.overrideWithValue(
      LocalProfileRepository(store: store, queries: queries, counters: counters),
    ),
    notificationRepositoryProvider.overrideWithValue(LocalNotificationRepository(store: store)),
    mediaRepositoryProvider.overrideWithValue(media),
    mediaStoreProvider.overrideWithValue(mediaStore),
  ];
}
