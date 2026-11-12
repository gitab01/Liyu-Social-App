import 'dart:async';

import 'package:liyu_social/data/local/local_store.dart';
import 'package:liyu_social/domain/models/user.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Phone-only auth for the local backend.
///
/// There is no SMS gateway and no credential store, so OTP codes are generated
/// in-process and surfaced back to the UI as [OtpChallenge.devCode]. The UI
/// shows them as a hint — a real Firebase build delivers the code over SMS and
/// leaves [devCode] null.
class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository(this._store) {
    _session = _store.sessionUid;
  }

  final LocalStore _store;
  final StreamController<UserProfile?> _authController = StreamController<UserProfile?>.broadcast();
  final Map<String, _PendingOtp> _pendingCodes = {};
  String? _session;

  @override
  Stream<UserProfile?> authState() async* {
    yield _currentUser();
    yield* _authController.stream;
  }

  @override
  Future<OtpChallenge> sendOtp(String phone) async {
    final normalised = _normalisePhone(phone);
    if (normalised.isEmpty) throw StateError('Enter a phone number with country code, like +251911…');
    final code = (100000 + _uuid.v4().hashCode.abs() % 900000).toString();
    final verificationId = _uuid.v4();
    _pendingCodes[verificationId] = _PendingOtp(phone: normalised, code: code, expiresAt: DateTime.now().add(const Duration(minutes: 5)));
    return OtpChallenge(verificationId: verificationId, devCode: code, expiresIn: const Duration(minutes: 5));
  }

  @override
  Future<UserProfile> signInWithOtp({required OtpChallenge challenge, required String code}) async {
    final pending = _pendingCodes[challenge.verificationId];
    if (pending == null) throw StateError('Code expired, request a new one');
    if (DateTime.now().isAfter(pending.expiresAt)) {
      _pendingCodes.remove(challenge.verificationId);
      throw StateError('Code expired, request a new one');
    }
    if (pending.code != code.trim()) throw StateError('That code is not correct');
    _pendingCodes.remove(challenge.verificationId);

    final user = _findOrCreateUser(pending.phone);
    await _store.setSession(user.uid);
    _session = user.uid;
    _authController.add(user);
    return user;
  }

  @override
  Future<UserProfile> signInWithEmail({required String email, required String password}) {
    throw UnsupportedError('Email sign-in requires the Firebase backend');
  }

  @override
  Future<UserProfile> register({
    required String displayName,
    String? phone,
    String? email,
    String? password,
    String languageCode = 'en',
  }) async {
    final uid = _uuid.v4();
    final user = UserProfile(
      uid: uid,
      displayName: displayName.trim(),
      phone: phone == null ? null : _normalisePhone(phone),
      email: email,
      languageCode: languageCode,
    );
    await _store.put('users', uid, user.toMap());
    await _store.setSession(uid);
    _session = uid;
    _authController.add(user);
    return user;
  }

  @override
  Future<UserProfile> updateProfile(UserProfile profile) async {
    await _store.update('users', profile.uid, profile.toMap());
    _authController.add(profile);
    return profile;
  }

  @override
  Future<void> signOut() async {
    await _store.setSession(null);
    _session = null;
    _authController.add(null);
  }

  UserProfile? _currentUser() {
    final uid = _session ?? _store.sessionUid;
    if (uid == null) return null;
    final doc = _store.doc('users', uid);
    return doc == null ? null : UserProfile.fromMap(doc);
  }

  UserProfile _findOrCreateUser(String phone) {
    for (final doc in _store.all('users')) {
      final user = UserProfile.fromMap(doc);
      if (user.phone == phone) return user;
    }
    final tail = phone.substring(phone.length - 4);
    final uid = _uuid.v4();
    final user = UserProfile(
      uid: uid,
      displayName: 'Member $tail',
      phone: phone,
    );
    _store.put('users', uid, user.toMap());
    return user;
  }

  static String _normalisePhone(String raw) {
    final stripped = raw.replaceAll(RegExp(r'[\s().-]'), '');
    if (stripped.isEmpty) return '';
    final prefixed = stripped.startsWith('+') ? stripped : '+$stripped';
    final digits = prefixed.replaceFirst('+', '');
    if (digits.length < 9 || digits.length > 15) return '';
    return '+$digits';
  }
}

class _PendingOtp {
  const _PendingOtp({required this.phone, required this.code, required this.expiresAt});
  final String phone;
  final String code;
  final DateTime expiresAt;
}
