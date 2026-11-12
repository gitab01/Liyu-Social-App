import 'dart:async';

import 'package:liyu_social/domain/repositories/repositories.dart';

/// Reports reachability of the backend.
///
/// Real connectivity comes from a platform reachability plugin; this build
/// carries an in-process implementation that is authoritative for the local
/// backend and can be driven by the settings screen or a test. Swapping in
/// `connectivity_plus` behind the same interface is the production path, which
/// is why nothing above this file reads anything but [online] and [changes].
class InProcessConnectionMonitor implements ConnectionMonitor {
  InProcessConnectionMonitor({bool offline = false}) : _simulatedOffline = offline;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  bool _networkAvailable = true;
  bool _simulatedOffline;

  @override
  bool get online => _networkAvailable && !_simulatedOffline;

  @override
  Stream<bool> get changes => _controller.stream;

  @override
  void setSimulatedOffline(bool offline) => _publish(() => _simulatedOffline = offline);

  /// Drive the network half directly, for reconnect tests that flip state
  /// mid-flow rather than through a user setting.
  void setNetworkAvailable(bool available) => _publish(() => _networkAvailable = available);

  void _publish(bool Function() mutate) {
    final before = online;
    mutate();
    final after = online;
    if (before != after) _controller.add(after);
  }

  Future<void> close() => _controller.close();
}
