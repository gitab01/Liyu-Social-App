import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/router/app_router.dart';
import 'package:liyu_social/data/firebase/fcm_notification_service.dart';
import 'package:liyu_social/data/firebase/firebase_bootstrap.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// Headless bridge between FCM and the router.
///
/// Push only exists once Firebase is configured, so on the local backend this
/// widget does nothing at all — it never touches the messaging plugin, which
/// would throw before `Firebase.initializeApp` has run. When Firebase *is* up it
/// registers the device token for the signed-in account (the single document the
/// fan-out function reads) and forwards every tapped notification's deep link to
/// [deepLinkProvider].
class PushLinker extends ConsumerStatefulWidget {
  const PushLinker({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PushLinker> createState() => _PushLinkerState();
}

class _PushLinkerState extends ConsumerState<PushLinker> {
  FcmNotificationService? _service;
  String? _registeredUid;

  @override
  void dispose() {
    _service?.dispose();
    super.dispose();
  }

  void _wire(FcmNotificationService service) {
    service.start();
    service.lastDeepLink.addListener(() {
      final link = service.lastDeepLink.value;
      if (link != null) ref.read(deepLinkProvider).value = link;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(backendModeProvider) != BackendMode.firebase) return widget.child;

    final service = ref.read(fcmServiceProvider);
    if (_service == null) {
      _service = service;
      _wire(service);
    }

    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user != null && user.uid != _registeredUid) {
      _registeredUid = user.uid;
      // Deliberately not awaited: a push-token write must never block a frame,
      // and a failure here only costs delivery until the next refresh.
      service
          .register(
            notifications: ref.read(notificationRepositoryProvider),
            uid: user.uid,
            languageCode: user.languageCode,
          )
          .catchError((Object _) {});
    }
    return widget.child;
  }
}
