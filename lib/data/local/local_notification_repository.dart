import 'package:liyu_social/data/local/local_store.dart';
import 'package:liyu_social/data/local/local_watch.dart';
import 'package:liyu_social/domain/models/notification.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// The notification tray.
///
/// Entries are written by the fan-out inside the other local repositories — the
/// same shape the Firebase build gets from Cloud Functions — and the device
/// token lives in `devices/{uid}`, the single document a push delivery reads.
class LocalNotificationRepository implements NotificationRepository {
  LocalNotificationRepository({required LocalStore store}) : _store = store;

  final LocalStore _store;

  @override
  Stream<List<AppNotification>> watch(String uid, {int limit = 30}) => watchCollections<List<AppNotification>>(
    _store,
    const ['notifications'],
    () {
      final list = _store
          .all('notifications')
          .map(AppNotification.fromMap)
          .where((n) => n.recipientUid == uid)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list.take(limit).toList();
    },
  );

  @override
  Future<void> markRead(String id) async {
    final doc = _store.doc('notifications', id);
    if (doc == null) return;
    await _store.update('notifications', id, {'readAt': DateTime.now()});
  }

  @override
  Future<void> markAllRead(String uid) async {
    for (final doc in _store.all('notifications')) {
      final notification = AppNotification.fromMap(doc);
      if (notification.recipientUid != uid || !notification.isUnread) continue;
      await _store.update('notifications', notification.id, {'readAt': DateTime.now()});
    }
  }

  @override
  Future<void> registerDeviceToken({required String uid, required String token}) =>
      _store.put('devices', uid, {'uid': uid, 'fcmToken': token, 'updatedAt': DateTime.now()});
}
