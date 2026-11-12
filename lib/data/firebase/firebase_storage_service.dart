import 'package:firebase_storage/firebase_storage.dart';
import 'package:liyu_social/core/offline/write_queue.dart';
import 'package:liyu_social/data/media/image_engine.dart';
import 'package:liyu_social/domain/models/media.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';
import 'package:uuid/uuid.dart';

/// Media pipeline + upload against Firebase Storage.
///
/// The heavy lifting already happened before this class is reached: `prepare`
/// just delegates to [ImageEngine], which downscales on-device so a mid-range
/// phone uploads a few hundred kilobytes instead of a five-megabyte original. The
/// upload then writes two JPEGs under the owner's own prefix — the compressed
/// image at `users/{uid}/{purpose}/{mediaId}` and its thumbnail alongside it —
/// matching the path the storage rules and `AccessRules.mediaPathFor` assume, so
/// one account can never overwrite another's media.
///
/// The whole transfer is handed to the offline [LocalWriteQueue]: unlike a
/// Firestore document write, a Storage upload does not survive a dropped socket,
/// so an offline publish must defer rather than fail.
class FirebaseMediaService implements MediaRepository {
  FirebaseMediaService({
    required LocalWriteQueue writeQueue,
    FirebaseStorage? storage,
    ImageEngine engine = const ImageEngine(),
  })  : _queue = writeQueue,
        _storage = storage ?? FirebaseStorage.instance,
        _engine = engine;

  final LocalWriteQueue _queue;
  final FirebaseStorage _storage;
  final ImageEngine _engine;
  static const Uuid _uuid = Uuid();

  /// mediaId -> its storage base path, so `delete` can find both objects.
  final Map<String, String> _paths = {};

  @override
  Future<PreparedMedia> prepare(SourceFile file, {int maxDimension = 1280, int quality = 80}) =>
      _engine.prepare(file, maxDimension: maxDimension, quality: quality);

  @override
  Future<MediaRef> upload({
    required String ownerUid,
    required PreparedMedia prepared,
    required MediaPurpose purpose,
    void Function(double progress)? onProgress,
  }) {
    // Deferred when offline, run inline when online. The mediaId is minted here,
    // before the queue may delay it, so a retry reuses the same object paths.
    final mediaId = _uuid.v4();
    final base = 'users/$ownerUid/${purpose.name}/$mediaId';
    return _queue.enqueue<MediaRef>(
      QueueKind.mediaUpload,
      'upload $purpose/$mediaId',
      () => _put(mediaId, base, prepared, onProgress),
    );
  }

  @override
  Future<void> delete(String mediaId) async {
    final base = _paths.remove(mediaId);
    if (base == null) return;
    // Both objects go together; a lone thumbnail left behind is billed storage a
    // reference no longer points at. Story objects are rejected here by the
    // storage rules — only the scheduled Function reclaims those — so each delete
    // is guarded individually and one failure cannot strand the other.
    try {
      await _storage.ref(base).delete();
    } on FirebaseException catch (_) {
      // Denied or already gone: fall through to the thumbnail.
    }
    try {
      await _storage.ref('$base/thumb.jpg').delete();
    } on FirebaseException catch (_) {
      // Same: best-effort reclaim of the thumbnail.
    }
  }

  Future<MediaRef> _put(
    String mediaId,
    String base,
    PreparedMedia prepared,
    void Function(double progress)? onProgress,
  ) async {
    final fullRef = _storage.ref(base);
    final thumbRef = _storage.ref('$base/thumb.jpg');
    // `contentType` is what the storage rules check and what a viewer needs to
    // decode inline; uploading raw bytes without it lands as an octet-stream.
    final metadata = SettableMetadata(contentType: 'image/jpeg');

    final totalBytes = prepared.bytes.length + prepared.thumbBytes.length;
    var fullTransferred = 0;
    var thumbTransferred = 0;

    void report(TaskSnapshot event, {required bool isFull}) {
      if (isFull) {
        fullTransferred = event.bytesTransferred;
      } else {
        thumbTransferred = event.bytesTransferred;
      }
      if (onProgress == null) return;
      final done = (fullTransferred + thumbTransferred) / (totalBytes == 0 ? 1 : totalBytes);
      onProgress(done.clamp(0, 1).toDouble());
    }

    final fullTask = fullRef.putData(prepared.bytes, metadata);
    final thumbTask = thumbRef.putData(prepared.thumbBytes, metadata);

    final fullSub = fullTask.snapshotEvents.listen((e) => report(e, isFull: true));
    final thumbSub = thumbTask.snapshotEvents.listen((e) => report(e, isFull: false));

    final fullSnapshot = await fullTask;
    final thumbSnapshot = await thumbTask;
    await fullSub.cancel();
    await thumbSub.cancel();

    final fullUrl = await fullSnapshot.ref.getDownloadURL();
    final thumbUrl = await thumbSnapshot.ref.getDownloadURL();
    onProgress?.call(1.0);

    _paths[mediaId] = base;
    return MediaRef(
      id: mediaId,
      thumbUrl: thumbUrl,
      fullUrl: fullUrl,
      aspectRatio: prepared.aspectRatio,
      originalBytes: prepared.originalBytes,
      uploadedBytes: prepared.bytes.length,
      thumbBytes: prepared.thumbBytes.length,
    );
  }
}
