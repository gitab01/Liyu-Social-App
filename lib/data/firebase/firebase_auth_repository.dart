import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:liyu_social/data/firebase/converters.dart';
import 'package:liyu_social/domain/models/user.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// Phone/email auth against Firebase, with the profile document kept in step.
///
/// Firebase Auth stores credentials; it does not store a `UserProfile`. So every
/// sign-in path resolves the matching `users/{uid}` document through
/// [_profileFor], creating it on first entry. That keeps `authState()` returning
/// the same shape the local backend returns, and it is what lets the app render
/// a name and avatar the instant a session appears instead of waiting on a
/// second round-trip.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users => _firestore.collection('users');

  @override
  Stream<UserProfile?> authState() => _auth.authStateChanges().asyncMap((user) async {
    if (user == null) return null;
    return _profileFor(user);
  });

  @override
  Future<OtpChallenge> sendOtp(String phone) async {
    final completer = Completer<OtpChallenge>();
    // verifyPhoneNumber drives through its callbacks: `codeSent` is the success
    // signal we turn into an OtpChallenge, and `verificationFailed` is the only
    // place a bad number surfaces. The returned Future mirrors those failures,
    // so it is awaited and re-routed rather than left dangling.
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (credential) {
          // Android can auto-resolve the SMS; sign straight through so a fast
          // device skips the manual code entry. The result is intentionally not
          // awaited — `codeSent` still fires and drives the UI — but the error
          // channel is attached so a failed auto-resolution cannot crash.
          unawaited(
            _auth.signInWithCredential(credential).then((_) {}, onError: (Object _) {}),
          );
        },
        verificationFailed: (error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
        codeSent: (verificationId, resendToken) {
          // devCode stays null: only the local backend can hand the code back,
          // Firebase delivers it over SMS.
          if (!completer.isCompleted) {
            completer.complete(OtpChallenge(verificationId: verificationId));
          }
        },
        codeAutoRetrievalTimeout: (verificationId) {},
      );
    } on FirebaseAuthException catch (error) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    return completer.future;
  }

  @override
  Future<UserProfile> signInWithOtp({required OtpChallenge challenge, required String code}) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: challenge.verificationId,
      smsCode: code,
    );
    final result = await _auth.signInWithCredential(credential);
    final user = result.user;
    if (user == null) throw StateError('phone sign-in returned no user');
    return _profileFor(user, createIfMissing: true);
  }

  @override
  Future<UserProfile> signInWithEmail({required String email, required String password}) async {
    final credential = EmailAuthProvider.credential(email: email, password: password);
    final result = await _auth.signInWithCredential(credential);
    final user = result.user;
    if (user == null) throw StateError('email sign-in returned no user');
    return _profileFor(user, createIfMissing: true);
  }

  @override
  Future<UserProfile> register({
    required String displayName,
    String? phone,
    String? email,
    String? password,
    String languageCode = 'en',
  }) async {
    User? user;
    if (email != null && password != null) {
      final result = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      user = result.user;
    } else {
      // A phone registration arrives here after the OTP sign-in, so the account
      // already exists and only the profile document is missing.
      user = _auth.currentUser;
    }
    if (user == null) throw StateError('could not create an account');

    final profile = UserProfile(
      uid: user.uid,
      displayName: displayName,
      photoUrl: user.photoURL,
      phone: phone ?? user.phoneNumber,
      email: email ?? user.email,
      languageCode: languageCode,
    );
    await _users.doc(user.uid).set(withTimestamps(profile.toMap()), SetOptions(merge: true));
    return profile;
  }

  @override
  Future<UserProfile> updateProfile(UserProfile profile) async {
    await _users.doc(profile.uid).set(withTimestamps(profile.toMap()), SetOptions(merge: true));
    return profile;
  }

  @override
  Future<void> signOut() => _auth.signOut();

  /// Reads `users/{uid}`, minting the document when a credential has no profile
  /// yet. `createIfMissing` is off during `authState()` — a cold start should not
  /// write — and on for an explicit sign-in, where the user genuinely just
  /// arrived.
  Future<UserProfile> _profileFor(User user, {bool createIfMissing = false}) async {
    final snapshot = await _users.doc(user.uid).get();
    if (snapshot.exists) return UserProfile.fromMap(domainMap(snapshot));

    final fallback = UserProfile(
      uid: user.uid,
      displayName: user.displayName ?? user.email ?? user.phoneNumber ?? 'Member',
      photoUrl: user.photoURL,
      phone: user.phoneNumber,
      email: user.email,
    );
    if (createIfMissing) {
      await _users.doc(user.uid).set(withTimestamps(fallback.toMap()), SetOptions(merge: true));
    }
    return fallback;
  }
}
