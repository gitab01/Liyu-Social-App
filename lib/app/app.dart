import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liyu_social/app/bootstrap.dart';
import 'package:liyu_social/app/bootstrap_result_provider.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/router/app_router.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/features/notifications/push_linker.dart';

class LiyuApp extends ConsumerWidget {
  const LiyuApp({required this.result, super.key});

  final BootstrapResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return PushLinker(
      child: MaterialApp.router(
        title: 'Liyu',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('am')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: createRouter(ref),
      ),
    );
  }
}

/// Appends the startup result so any screen can explain the backend choice.
List<Override> withBootstrapResult(List<Override> overrides, BootstrapResult result) => [
  ...overrides,
  bootstrapResultProvider.overrideWithValue(result),
];
