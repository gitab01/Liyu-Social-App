import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// Push plumbing: permission, token registration, and forwarding a tapped
/// notification's deep link to a [lastDeepLink] the router can listen to.
///
/// A push is the one signal that must reach the user even when the app is not
/// open, which is exactly the path that is hardest to test. This service owns the
/// three delivery moments — a message while foreground (`onMessage`), a tap after
/// the app was backgrounded (`onMessageOpenedApp`), and a tap that cold-launched
/// it (`getInitialMessage`) — and collapses them into one `ValueNotifier<String?>`
/// so the router treats a cold start and a warm tap identically. The token is
/// written to `devices/{uid}` through [NotificationRepository], the single doc
/// the message Fan-Out function reads to deliver.
class FcmNotificationService {
  FcmNotificationService({FirebaseMessaging? messaging}) : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  /// Route the router opens when a push is tapped. `null` means "no pending
  /// navigation" so a listener that fires late does not re-route.
  final ValueNotifier<String?> lastDeepLink = ValueNotifier<String?>(null);

  /// Body text of the most recent foreground message, localized for the reader —
  /// a foreground notification is shown in-app because no system tray slot is
  /// free while the app is open.
  final ValueNotifier<String?> foregroundBody = ValueNotifier<String?>(null);

  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenSub;
  String _languageCode = 'en';

  /// Prompts for permission and reports whether it was granted. iOS provisional
  /// delivery counts as usable; a denial does not, and the caller can then steer
  /// the user to settings rather than silently never receiving a push.
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(alert: true, badge: true, sound: true);
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<String?> token() => _messaging.getToken();

  /// Requests permission, mints the token, registers it under `devices/{uid}`,
  /// and keeps it registered across refreshes — FCM rotates tokens on iOS
  /// reinstalls and Android periodic refreshes, and a stale token is a silent
  /// delivery failure.
  Future<void> register({
    required NotificationRepository notifications,
    required String uid,
    String languageCode = 'en',
  }) async {
    _languageCode = languageCode;
    await requestPermission();
    final initial = await token();
    if (initial != null) await notifications.registerDeviceToken(uid: uid, token: initial);
    _tokenSub?.cancel();
    _tokenSub = _messaging.onTokenRefresh.listen((refreshed) {
      notifications.registerDeviceToken(uid: uid, token: refreshed);
    });
  }

  /// Attaches the delivery listeners. Called once after startup.
  void start() {
    // The background isolate handler must be a top-level function, so it is set
    // here from an entry point that itself cannot hold instance state.
    FirebaseMessaging.onBackgroundMessage(liyuBackgroundMessageHandler);

    _onMessageSub = FirebaseMessaging.onMessage.listen((message) {
      foregroundBody.value = localizedBody(
        type: NotificationType.parse(message.data['type'] as String?),
        actorName: (message.data['actorName'] as String?) ?? '',
        languageCode: _languageCode,
      );
      final deepLink = _deepLinkOf(message);
      if (deepLink != null) lastDeepLink.value = deepLink;
    });

    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final deepLink = _deepLinkOf(message);
      if (deepLink != null) lastDeepLink.value = deepLink;
    });

    // App cold-launched from a notification tap: the message is not in any
    // stream, it is read once here.
    _messaging.getInitialMessage().then((message) {
      final deepLink = message == null ? null : _deepLinkOf(message);
      if (deepLink != null) lastDeepLink.value = deepLink;
    });
  }

  /// A push body in the reader's language. The Cloud Function that fans out the
  /// notification reads `users/{uid}.languageCode` and could send the text
  /// directly; this client-side copy keeps the foreground banner honest even when
  /// the payload carries only a type and an actor.
  String localizedBody({required NotificationType type, required String actorName, required String languageCode}) {
    final amharic = languageCode == 'am';
    final who = actorName.trim();
    return switch (type) {
      NotificationType.message => amharic ? '$who ቅሬታ ልኳልዎታል' : '$who sent you a message',
      NotificationType.like => amharic ? '$who ልጥፍዎን ወድዷል' : '$who liked your post',
      NotificationType.comment => amharic ? '$who ላይ አስተያየት ሰጥቷል' : '$who commented on your post',
      NotificationType.follow => amharic ? '$who እየተከተሉዎት ነው' : '$who started following you',
      NotificationType.mention => amharic ? '$who ስምዎን አወሳል' : '$who mentioned you',
    };
  }

  String? _deepLinkOf(RemoteMessage message) {
    final link = message.data['deepLink'];
    return link is String && link.isNotEmpty ? link : null;
  }

  /// Tears down listeners and notifiers. Safe to call from a provider's `onDispose`.
  void dispose() {
    _onMessageSub?.cancel();
    _openedSub?.cancel();
    _tokenSub?.cancel();
    lastDeepLink.dispose();
    foregroundBody.dispose();
  }
}

/// Background message handler. It must be top-level (and entry-point-pragma'd)
/// because FCM runs it in its own isolate with no access to provider state. The
/// plugin has already shown the system notification by the time this runs, so the
/// handler only needs to exist and resolve; anything heavier belongs in a data
/// extension, not the callback thread.
@pragma('vm:entry-point')
Future<void> liyuBackgroundMessageHandler(RemoteMessage message) async {
  debugPrint('liyu: background push ${message.messageId} -> ${message.data['deepLink']}');
}
