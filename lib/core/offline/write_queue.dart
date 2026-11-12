import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

enum QueueKind { mediaUpload, postPublish, storyPublish, message, reaction }

/// A deferred network write, kept until it has been delivered or has failed.
class _QueuedWrite {
  _QueuedWrite({required this.kind, required this.label, required this.operation});

  final QueueKind kind;
  final String label;
  final Future<Object?> Function() operation;
  final Completer<Object?> completer = Completer<Object?>();
}

/// Holds writes attempted while there is no connection, and replays them when
/// one returns.
///
/// Firestore persists its own document writes offline, but Storage uploads and
/// message sends do not survive a dropped socket, and a send attempted during a
/// drop is exactly where duplicates and silent losses appear. So one owner
/// decides "when do we retry", and each caller re-runs the identical operation —
/// which is safe only because message and post ids are minted on the client.
class LocalWriteQueue {
  LocalWriteQueue({required ConnectionMonitor monitor}) {
    _online = monitor.online;
    _sub = monitor.changes.listen((online) {
      _online = online;
      if (online) flush();
    });
  }

  final List<_QueuedWrite> _pending = [];
  StreamSubscription<bool>? _sub;
  late bool _online;

  /// Observable so the UI can show a sync badge without polling.
  final ValueNotifier<int> pendingWrites = ValueNotifier<int>(0);

  bool get hasPending => _pending.isNotEmpty;

  /// Runs immediately when online. Offline, the returned future completes only
  /// once the write is actually delivered, so a caller can honestly say "saved
  /// offline — will publish when you reconnect".
  Future<T> enqueue<T>(QueueKind kind, String label, Future<T> Function() operation) {
    if (_online) return operation();

    final entry = _QueuedWrite(
      kind: kind,
      label: label,
      operation: () async => await operation() as Object?,
    );
    _pending.add(entry);
    pendingWrites.value = _pending.length;

    return entry.completer.future.then((value) => value as T);
  }

  Future<void> flush() async {
    if (_pending.isEmpty) return;
    final batch = List.of(_pending);
    _pending.clear();
    pendingWrites.value = 0;

    for (final entry in batch) {
      try {
        final value = await entry.operation();
        if (!entry.completer.isCompleted) entry.completer.complete(value);
      } on Object catch (error, stack) {
        if (!entry.completer.isCompleted) entry.completer.completeError(error, stack);
      }
    }
  }

  /// Test seam: force the connection state without a monitor.
  set assumeOnline(bool value) => _online = value;

  void dispose() {
    _sub?.cancel();
    for (final entry in _pending) {
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(StateError('write queue disposed with ${entry.label} pending'));
      }
    }
    _pending.clear();
    pendingWrites.dispose();
  }
}
