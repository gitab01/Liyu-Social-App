import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liyu_social/app/app.dart';
import 'package:liyu_social/app/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // After `flutterfire configure`, uncomment alongside the generated import:
  // registerFirebaseOptions(() => DefaultFirebaseOptions.currentPlatform);
  final result = await bootstrap();
  runApp(
    ProviderScope(
      overrides: withBootstrapResult(result.overrides, result),
      child: LiyuApp(result: result),
    ),
  );
}
