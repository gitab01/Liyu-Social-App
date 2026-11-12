import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// Turns a platform picker result into the app's own [SourceFile].
///
/// The picker is called with no `maxWidth` and no `imageQuality`: downsampling
/// there would hide bytes from the compression pipeline and make the "saved on
/// data" figure a lie. Every file arrives at full size and is shrunk by the
/// media service, which is the step the whole cost story depends on.
///
/// On web there is no filesystem, so the bytes are read here and carried with
/// the reference; on mobile the path is enough and the engine streams it later.
Future<List<SourceFile>> pickGalleryImages({int maxItems = 4}) async {
  final picked = await ImagePicker().pickMultiImage(imageQuality: 100);
  return _all(picked.take(maxItems).toList());
}

Future<List<SourceFile>> pickCameraPhoto() async {
  try {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 100);
    return picked == null ? const [] : await _all([picked]);
  } on Exception {
    // No camera on web, desktop, or an emulator without one.
    return const [];
  }
}

Future<List<SourceFile>> _all(List<XFile> files) => Future.wait(files.map(_one));

Future<SourceFile> _one(XFile file) async => SourceFile(
  path: file.path,
  name: file.name,
  sizeBytes: await file.length(),
  bytes: kIsWeb ? await file.readAsBytes() : null,
);
