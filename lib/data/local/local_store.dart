import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A document store on top of `SharedPreferences`, with the shape a client
/// needs from a real backend: collections of documents, change streams, and
/// durable writes.
///
/// This is what lets the whole app — auth, feed, stories, DMs, notifications —
/// run and be tested with no project credentials. Writes are applied
/// immediately and flushed to disk on a short debounce, which mirrors the
/// "accept now, sync soon" behaviour the product depends on.
class LocalStore {
  LocalStore._(this._prefs);

  static const String _dataKey = 'liyu.local.data.v1';
  static const String _sessionKey = 'liyu.local.session.v1';
  static const Duration _flushDelay = Duration(milliseconds: 250);

  static Future<LocalStore> open(SharedPreferences prefs) async {
    final store = LocalStore._(prefs);
    await store._hydrate();
    return store;
  }

  final SharedPreferences _prefs;
  final Map<String, Map<String, Map<String, Object?>>> _collections = {};
  final Map<String, StreamController<List<Map<String, Object?>>>> _watchers = {};

  Timer? _flushTimer;
  bool _disposed = false;

  Future<void> _hydrate() async {
    final raw = _prefs.getString(_dataKey);
    if (raw == null) return;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    for (final entry in decoded.entries) {
      final docs = (entry.value as Map).map<String, Map<String, Object?>>(
        (id, doc) => MapEntry(id as String, _decodeDoc((doc as Map).cast<String, Object?>())),
      );
      _collections[entry.key] = docs;
    }
  }

  /// Called once after startup so a first run is not an empty shell.
  Future<void> seedIfEmpty(Map<String, Map<String, Map<String, Object?>>> seed) async {
    if (_collections.isNotEmpty) return;
    seed.forEach((collection, docs) {
      docs.forEach((id, doc) => _write(collection, id, doc, notify: false));
    });
    await _flushNow();
    _collections.keys.forEach(_notify);
  }

  List<Map<String, Object?>> all(String collection) {
    final docs = _collections[collection];
    if (docs == null) return const [];
    return docs.values.toList();
  }

  Map<String, Object?>? doc(String collection, String id) => _collections[collection]?[id];

  /// Merge into an existing document, creating it when absent.
  Future<void> update(String collection, String id, Map<String, Object?> patch) {
    final existing = _collections[collection]?[id] ?? <String, Object?>{};
    final merged = {...existing, ...patch};
    _write(collection, id, merged, notify: true);
    return Future.value();
  }

  Future<void> put(String collection, String id, Map<String, Object?> value) {
    _write(collection, id, value, notify: true);
    return Future.value();
  }

  /// Idempotent upsert: the same id written twice leaves one document. This is
  /// the property that makes a retried message send safe.
  Future<void> upsert(String collection, String id, Map<String, Object?> value) => put(collection, id, value);

  Future<void> delete(String collection, String id) {
    _collections[collection]?.remove(id);
    _scheduleFlush();
    _notify(collection);
    return Future.value();
  }

  Stream<List<Map<String, Object?>>> watch(String collection) {
    final controller = _watchers.putIfAbsent(
      collection,
      () => StreamController<List<Map<String, Object?>>>.broadcast(),
    );
    // A new listener is served the current contents immediately, which is what
    // lets a cold start paint the last-seen feed instead of a spinner.
    scheduleMicrotask(() {
      if (!controller.isClosed) controller.add(all(collection));
    });
    return controller.stream;
  }

  String? get sessionUid => _prefs.getString(_sessionKey);

  Future<void> setSession(String? uid) async {
    if (uid == null) {
      await _prefs.remove(_sessionKey);
    } else {
      await _prefs.setString(_sessionKey, uid);
    }
  }

  void _write(String collection, String id, Map<String, Object?> value, {required bool notify}) {
    _collections.putIfAbsent(collection, () => {})[id] = value;
    _scheduleFlush();
    if (notify) _notify(collection);
  }

  void _notify(String collection) {
    final controller = _watchers[collection];
    if (controller == null || controller.isClosed) return;
    controller.add(all(collection));
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushDelay, _flushNow);
  }

  Future<void> _flushNow() async {
    if (_disposed) return;
    final encoded = jsonEncode(
      _collections.map(
        (name, docs) => MapEntry(name, docs.map((id, doc) => MapEntry(id, _encodeDoc(doc)))),
      ),
    );
    await _prefs.setString(_dataKey, encoded);
  }

  /// Encodes values the JSON layer cannot hold — notably [DateTime], which
  /// Firestore would receive as a native timestamp instead.
  static Object? _encodeValue(Object? value) {
    if (value == null) return null;
    if (value is List) return value.map(_encodeValue).toList();
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _encodeValue(v)));
    }
    if (value is DateTime) return {'@type': 'datetime', 'value': value.toUtc().toIso8601String()};
    return value;
  }

  static Map<String, Object?> _encodeDoc(Map<String, Object?> doc) =>
      doc.map((k, v) => MapEntry(k, _encodeValue(v)));

  static Object? _decodeValue(Object? value) {
    if (value is Map) {
      final map = value.cast<String, Object?>();
      if (map['@type'] == 'datetime') return DateTime.parse(map['value'] as String).toLocal();
      return map.map((k, v) => MapEntry(k, _decodeValue(v)));
    }
    if (value is List) return value.map(_decodeValue).toList();
    return value;
  }

  static Map<String, Object?> _decodeDoc(Map<String, Object?> doc) =>
      doc.map((k, v) => MapEntry(k, _decodeValue(v)));

  Future<void> dispose() async {
    _flushTimer?.cancel();
    await _flushNow();
    _disposed = true;
    for (final controller in _watchers.values) {
      await controller.close();
    }
    _watchers.clear();
  }

  /// Test hook: force a synchronous drain so assertions can read persisted state.
  Future<void> flushForTest() => _flushNow();
}
