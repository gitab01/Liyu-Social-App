import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// A reference to a media object that went through the client-side pipeline:
/// a downscaled original plus a small thumbnail generated next to it.
///
/// Both URLs are nullable on purpose. Feed rows are built from thumbnails, so
/// a post can be rendered as soon as its document arrives, before the
/// full-resolution object is resolved. When neither url is available the UI
/// paints a deterministic placeholder keyed on [id] rather than blocking on a
/// download.
class MediaRef extends Equatable {
  const MediaRef({
    required this.id,
    this.thumbUrl,
    this.fullUrl,
    this.aspectRatio = 1,
    this.originalBytes,
    this.uploadedBytes,
    this.thumbBytes,
    this.uploadFailed = false,
  });

  final String id;
  final String? thumbUrl;
  final String? fullUrl;

  /// Width / height, stored so list tiles can reserve their scroll height
  /// before any pixel loads.
  final double aspectRatio;

  final int? originalBytes;
  final int? uploadedBytes;
  final int? thumbBytes;
  final bool uploadFailed;

  /// Bytes saved by compressing before upload, or null when unknown.
  int? get savedBytes {
    final o = originalBytes, u = uploadedBytes;
    if (o == null || u == null || u > o) return null;
    return o - u;
  }

  MediaRef copyWith({
    String? thumbUrl,
    String? fullUrl,
    int? uploadedBytes,
    int? thumbBytes,
    bool? uploadFailed,
  }) {
    return MediaRef(
      id: id,
      thumbUrl: thumbUrl ?? this.thumbUrl,
      fullUrl: fullUrl ?? this.fullUrl,
      aspectRatio: aspectRatio,
      originalBytes: originalBytes,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      thumbBytes: thumbBytes ?? this.thumbBytes,
      uploadFailed: uploadFailed ?? this.uploadFailed,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'thumbUrl': thumbUrl,
    'fullUrl': fullUrl,
    'aspectRatio': aspectRatio,
    'originalBytes': originalBytes,
    'uploadedBytes': uploadedBytes,
    'thumbBytes': thumbBytes,
    'uploadFailed': uploadFailed,
  };

  static MediaRef fromMap(Map<String, dynamic>? map) {
    if (map == null) return const MediaRef(id: '');
    return MediaRef(
      id: map['id'] as String? ?? '',
      thumbUrl: map['thumbUrl'] as String?,
      fullUrl: map['fullUrl'] as String?,
      aspectRatio: (map['aspectRatio'] as num?)?.toDouble() ?? 1,
      originalBytes: (map['originalBytes'] as num?)?.toInt(),
      uploadedBytes: (map['uploadedBytes'] as num?)?.toInt(),
      thumbBytes: (map['thumbBytes'] as num?)?.toInt(),
      uploadFailed: map['uploadFailed'] as bool? ?? false,
    );
  }

  bool get isEmpty => id.isEmpty;

  @override
  List<Object?> get props => [id, thumbUrl, fullUrl, aspectRatio, uploadedBytes, thumbBytes, uploadFailed];
}

/// Result of running a picked file through the compression pipeline, before
/// any network call happens.
class PreparedMedia {
  const PreparedMedia({
    required this.bytes,
    required this.thumbBytes,
    required this.aspectRatio,
    required this.originalBytes,
  });

  final Uint8List bytes;
  final Uint8List thumbBytes;
  final double aspectRatio;
  final int originalBytes;
}
