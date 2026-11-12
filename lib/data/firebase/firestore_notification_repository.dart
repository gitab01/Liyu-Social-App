import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:liyu_social/data/firebase/converters.dart';
import 'package:liyu_social/domain/models/notification.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// The notification tray against `notifications`, plus device registration in
/// `devices`.
///
/// Notification documents are created by Cloud Functions, never by the client;
/// this repository only reads them and marks them read. A document is filtered by
/// `recipientUid` and the rules let only that recipient touch it, which is why a
/// badge count never leaks across accounts. `registerDeviceToken` writes one
/// `devices/{uid}` doc per account — Functions read that single doc to send a
/// push, so keeping it keyed by uid is what makes delivery a direct lookup rather
/// than a token search.
class FirestoreNotificationRepository implements NotificationRepository {
  FirestoreNotificationRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _notifications => _firestore.collection('notifications');
  CollectionReference<Map<String, dynamic>> get _devices => _firestore.collection('devices');

  @override
  Stream<List<AppNotification>> watch(String uid, {int limit = 30}) {
    return _notifications
        .where('recipientUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AppNotification.fromMap(domainMap(d))).toList());
  }

  @override
  Future<void> markRead(String id) {
    return _notifications.doc(id).update({'readAt': Timestamp.now()});
  }

  @override
  Future<void> markAllRead(String uid) async {
    final unread = await _notifications.where('recipientUid', isEqualTo: uid).where('readAt', isNull: true).get();
    if (unread.docs.isEmpty) return;
    final batch = _firestore.batch();
    final now = Timestamp.now();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'readAt': now});
    }
    await batch.commit();
  }

  @override
  Future<void> registerDeviceToken({required String uid, required String token}) {
    return _devices.doc(uid).set({'fcmToken': token, 'updatedAt': Timestamp.now()}, SetOptions(merge: true));
  }
}
