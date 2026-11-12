import 'package:liyu_social/core/offline/write_queue.dart';
import 'package:liyu_social/data/media/image_engine.dart';
import 'package:liyu_social/data/media/media_store.dart';
import 'package:liyu_social/domain/access_rules.dart';
import 'package:liyu_social/domain/models/media.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Media storage for the local backend: the real compression pipeline, then
/// bytes held in-process instead of a Storage bucket.
///
/// The reference intentionally carries no download urls. The UI resolves a
/// missing url by looking the media id up in [MediaStore], and paints a
/// deterministic placeholder when even that misses — which is the same code path
/// a post takes when its media has not arrived yet on a real connection.
class LocalMediaService implements MediaRepository {
  LocalMediaService({
    required MediaStore mediaStore,
    required LocalWriteQueue queue,
    ImageEngine engine = const ImageEngine(),
  })  : _mediaStore = mediaStore,
        _queue = queue,
        _engine = engine;

  final MediaStore _mediaStore;
  final LocalWriteQueue _queue;
  final ImageEngine _engine;

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
    final mediaId = _uuid.v4();
    final path = AccessRules.mediaPathFor(uid: ownerUid, purpose: purpose.name, mediaId: mediaId);
    if (!AccessRules.canWriteMediaPath(path: path, uid: ownerUid)) {
      throw StateError('permission-denied: media must live under your own path');
    }

    return _queue.enqueue(QueueKind.mediaUpload, path, () async {
      // Three ticks rather than one so a caller that renders progress is
      // exercising the same shape it will see from a real upload task.
      onProgress?.call(0.3);
      _mediaStore.put('full:$path', prepared.bytes);
      onProgress?.call(0.8);
      _mediaStore.put('thumbnail:$path', prepared.thumbBytes);
      onProgress?.call(1);

      return MediaRef(
        id: path,
        aspectRatio: prepared.aspectRatio,
        originalBytes: prepared.originalBytes,
        uploadedBytes: prepared.bytes.length,
        thumbBytes: prepared.thumbBytes.length,
      );
    });
  }

  @override
  Future<void> delete(String mediaId) async {
    _mediaStore.remove('full:$mediaId');
    _mediaStore.remove('thumbnail:$mediaId');
  }
}
