import 'dart:async';

import 'package:liyu_social/data/local/local_store.dart';

/// Re-runs [read] whenever any of [collections] changes.
///
/// A feed row is not a function of one collection: visibility depends on the
/// post, the follow graph and the block lists. Subscribing to each and
/// recomputing keeps a single source of truth per screen without one giant
/// denormalized document.
Stream<T> watchCollections<T>(
  LocalStore store,
  List<String> collections,
  T Function() read,
) {
  final controller = StreamController<T>.broadcast(sync: true);
  final subscriptions = <StreamSubscription<dynamic>>[];

  controller.onListen = () {
    for (final collection in collections) {
      subscriptions.add(store.watch(collection).listen((_) => controller.add(read())));
    }
  };
  controller.onCancel = () async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    subscriptions.clear();
  };

  return controller.stream;
}
