import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:liyu_social/domain/models/media.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// The on-device half of the media pipeline: a picked file goes in, a downscaled
/// JPEG and a small thumbnail come out, and nothing has touched the network.
///
/// Media is the cost driver in this app, so this step decides what every viewer
/// pays. The native path uses the platform codec, which keeps image decoding off
/// the UI isolate; where that is unavailable or fails — web, desktop, an odd
/// HEIC — the pipeline degrades to a `dart:ui` decode/encode rather than
/// dropping the post.
class ImageEngine {
  const ImageEngine();

  static const int thumbDimension = 320;

  Future<PreparedMedia> prepare(SourceFile source, {int maxDimension = 1280, int quality = 80}) async {
    final original = await readSourceBytes(source);
    final full = await _compress(original, maxDimension, quality) ?? original;
    final thumb = await _compress(full, thumbDimension, 70) ?? full;
    final aspect = await _aspectRatio(full) ?? await _aspectRatio(original) ?? 1;

    return PreparedMedia(
      bytes: full,
      thumbBytes: thumb,
      aspectRatio: aspect,
      originalBytes: original.length,
    );
  }

  Future<Uint8List?> _compress(Uint8List bytes, int maxDimension, int quality) async {
    if (!kIsWeb) {
      try {
        final out = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: maxDimension,
          minHeight: maxDimension,
          quality: quality,
          format: CompressFormat.jpeg,
        );
        if (out.isNotEmpty) return out;
      } on Object {
        // Native codec unavailable on this platform: fall through.
      }
    }
    try {
      return await _uiEncode(bytes, maxDimension);
    } on Object {
      return null;
    }
  }

  Future<Uint8List> _uiEncode(Uint8List bytes, int maxDimension) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final target = _targetSize(descriptor.width, descriptor.height, maxDimension);
    descriptor.dispose();
    buffer.dispose();

    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: target?.width.round(),
      targetHeight: target?.height.round(),
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      // dart:ui can only encode PNG here, which ignores the quality knob — this
      // fallback costs more data than the native JPEG path, so it exists to keep
      // a post publishable on platforms without the codec, not to replace it.
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('image could not be re-encoded');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// One side is enough: the codec scales the other proportionally, and asking
  /// it to do the work avoids allocating a full-resolution bitmap on a
  /// mid-range phone.
  ui.Size? _targetSize(int width, int height, int maxDimension) {
    final longest = width > height ? width : height;
    if (longest <= maxDimension) return null;
    final factor = maxDimension / longest;
    return ui.Size((width * factor).roundToDouble(), (height * factor).roundToDouble());
  }

  Future<double?> _aspectRatio(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final ratio = descriptor.width / descriptor.height;
      descriptor.dispose();
      buffer.dispose();
      return ratio;
    } on Object {
      return null;
    }
  }
}

/// Reads the picked file where a filesystem exists. On web the picker already
/// handed over the bytes.
Future<Uint8List> readSourceBytes(SourceFile source) async {
  final provided = source.bytes;
  if (provided != null) return provided;
  if (source.path.isEmpty) throw StateError('no bytes available for ${source.name}');
  return XFile(source.path).readAsBytes();
}
