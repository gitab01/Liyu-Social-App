import 'dart:typed_data';

/// Holds the bytes the running process produced, keyed by media id.
///
/// This exists so the local backend can round-trip a real upload — compress,
/// "store", read back — without a filesystem or a Storage bucket. Anything with
/// a remote url bypasses it entirely; the UI treats a miss here as "not local"
/// and falls back to a generated placeholder.
class MediaStore {
  MediaStore({this.maxRetainedBytes = 64 * 1024 * 1024});

  final int maxRetainedBytes;
  final Map<String, Uint8List> _objects = {};
  final List<String> _insertionOrder = [];

  void put(String id, Uint8List bytes) {
    if (_objects.containsKey(id)) {
      _objects[id] = bytes;
      return;
    }
    _objects[id] = bytes;
    _insertionOrder.add(id);
    _evictIfNeeded();
  }

  Uint8List? bytes(String id) => _objects[id];

  bool contains(String id) => _objects.containsKey(id);

  void remove(String id) {
    _objects.remove(id);
    _insertionOrder.remove(id);
  }

  int get retainedBytes => _objects.values.fold(0, (sum, b) => sum + b.length);

  void clear() {
    _objects.clear();
    _insertionOrder.clear();
  }

  /// Media on a mid-range phone cannot be cached forever. Oldest-first eviction
  /// keeps the working set to a bounded footprint.
  void _evictIfNeeded() {
    while (retainedBytes > maxRetainedBytes && _insertionOrder.isNotEmpty) {
      _objects.remove(_insertionOrder.removeAt(0));
    }
  }
}
