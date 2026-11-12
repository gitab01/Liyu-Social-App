import 'package:liyu_social/app/bootstrap.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lets the settings screen state which backend actually came up, rather than
/// which one was asked for.
final bootstrapResultProvider = Provider<BootstrapResult>(
  (ref) => throw StateError('bootstrapResultProvider must be overridden in main'),
);
