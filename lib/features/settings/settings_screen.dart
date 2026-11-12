import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liyu_social/app/bootstrap_result_provider.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/core/widgets/layout.dart';
import 'package:liyu_social/core/widgets/state_views.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// Appearance, language, data budget, connection and the backend that actually
/// came up.
///
/// Every switch here is stored before it is applied, so a phone that loses the
/// app mid-scroll comes back with the same settings. The backend row reports
/// what happened at startup rather than what was asked for, because "Firebase
/// was requested but could not initialize" is the difference between a bug and
/// a demo build.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final prefs = ref.read(sharedPreferencesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.settings)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          const OfflineBanner(),
          SectionHeader(title: t.theme, raised: true),
          _LabelledSegments(
            label: t.language,
            child: _LanguageRow(
              onChange: (code) {
                prefs.setString('ui.languageCode', code);
                ref.read(localeProvider.notifier).state = Locale(code);
              },
            ),
          ),
          _LabelledSegments(
            label: t.theme,
            child: _ThemeRow(
              onChange: (mode) {
                prefs.setString('ui.themeMode', mode.name);
                ref.read(themeModeProvider.notifier).state = mode;
              },
            ),
          ),
          const SectionDivider(),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
            title: Text(t.dataSaver),
            subtitle: Text(t.dataSaverHint),
            value: ref.watch(dataSaverProvider),
            onChanged: (value) {
              prefs.setBool('ui.dataSaver', value);
              ref.read(dataSaverProvider.notifier).state = value;
            },
          ),
          SectionHeader(title: t.offline, raised: true),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
            title: Text(t.simulateOffline),
            subtitle: const _QueueSummary(),
            value: ref.watch(offlineSimulatedProvider),
            onChanged: (value) {
              prefs.setBool('net.simulatedOffline', value);
              ref.read(offlineSimulatedProvider.notifier).state = value;
              ref.read(connectionMonitorProvider).setSimulatedOffline(value);
            },
          ),
          SectionHeader(title: t.backend, raised: true),
          const _BackendRow(),
          SectionHeader(title: t.account, raised: true),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text(t.signOut),
            onTap: () => _confirmSignOut(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final t = context.t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.signOut),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.signOut),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authRepositoryProvider).signOut().catchError((Object _) {});
  }
}

/// A caption above a control, so a group of segmented buttons reads as a form
/// rather than a row of unexplained switches.
class _LabelledSegments extends StatelessWidget {
  const _LabelledSegments({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, AppSpacing.m),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.s),
        child,
      ],
    ),
  );
}

class _LanguageRow extends ConsumerWidget {
  const _LanguageRow({required this.onChange});

  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final code = ref.watch(localeProvider).languageCode;
    return SegmentedButton<String>(
      segments: [
        ButtonSegment(value: 'en', label: Text(t.english)),
        ButtonSegment(value: 'am', label: Text(t.amharic)),
      ],
      selected: {code},
      onSelectionChanged: (selection) => onChange(selection.first),
    );
  }
}

class _ThemeRow extends ConsumerWidget {
  const _ThemeRow({required this.onChange});

  final ValueChanged<ThemeMode> onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final mode = ref.watch(themeModeProvider);
    return SegmentedButton<ThemeMode>(
      segments: [
        ButtonSegment(value: ThemeMode.system, label: Text(t.system)),
        ButtonSegment(value: ThemeMode.light, label: Text(t.light)),
        ButtonSegment(value: ThemeMode.dark, label: Text(t.dark)),
      ],
      selected: {mode},
      onSelectionChanged: (selection) => onChange(selection.first),
    );
  }
}

/// The queue count moves as writes flush, so this row listens on the notifier
/// instead of reading it once at build time.
class _QueueSummary extends ConsumerWidget {
  const _QueueSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    return ValueListenableBuilder<int>(
      valueListenable: ref.watch(pendingWritesProvider),
      builder: (context, count, _) => Text(
        count == 0 ? t.endOfFeed : '${t.queuedForSync} · $count',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _BackendRow extends ConsumerWidget {
  const _BackendRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    final result = ref.watch(bootstrapResultProvider);
    final usingFirebase = result.backend == BackendMode.firebase;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      leading: Icon(usingFirebase ? Icons.cloud_outlined : Icons.phone_android_outlined),
      title: Text(usingFirebase ? t.backendFirebase : t.backendLocal),
      subtitle: result.firebaseFailure == null
          ? null
          : Text(
              result.firebaseFailure!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
    );
  }
}
