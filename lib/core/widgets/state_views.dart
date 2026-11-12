import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';

/// Placeholders state its own reason. A blank feed because you follow nobody is
/// a different message from a blank feed because the read was denied.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    this.detail,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  final String title;
  final String? detail;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: scheme.onSurface.withValues(alpha: 0.35)),
            const SizedBox(height: AppSpacing.m),
            Text(title, textAlign: TextAlign.center, style: text.titleMedium),
            if (detail != null) ...[
              const SizedBox(height: AppSpacing.s),
              Text(detail!, textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: scheme.onSurface.withValues(alpha: 0.6))),
            ],
            if (action != null) ...[const SizedBox(height: AppSpacing.l), action!],
          ],
        ),
      ),
    );
  }
}

/// A failed read degrades to a retry control. Permission-denied specifically
/// falls back to a logged-out-shaped view rather than crashing the list.
class FailureView extends StatelessWidget {
  const FailureView({required this.error, this.onRetry, super.key});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final denied = error.toString().contains('permission-denied') || error is _PermissionDeniedMarker;
    return EmptyState(
      icon: denied ? Icons.lock_outline : Icons.wifi_off_rounded,
      title: denied ? context.t.permissionDenied : context.t.somethingWentWrong,
      detail: denied ? null : error.toString(),
      action: onRetry == null
          ? null
          : FilledButton(onPressed: onRetry, child: Text(context.t.tryAgain)),
    );
  }
}

/// Marker used by repositories to say "the rules refused this read" without
/// leaking a backend-specific exception type into the UI.
class _PermissionDeniedMarker {
  const _PermissionDeniedMarker();
}

const Object permissionDeniedMarker = _PermissionDeniedMarker();

/// Banner shown while the client cannot reach the backend. It names the queue,
/// because the useful information offline is that writes are not lost.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(connectionOnlineProvider);
    if (online) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.s),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outline))),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 16, color: scheme.onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Text(context.t.offlineBanner, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}

/// Async boundary helper: every screen renders the same three failure shapes,
/// so the mapping lives once.
class AsyncView<T> extends ConsumerWidget {
  const AsyncView({required this.value, required this.data, super.key});

  final AsyncValue<T> value;
  final Widget Function(T data) data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return value.when(
      data: data,
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.xxl), child: CircularProgressIndicator())),
      error: (error, _) => FailureView(error: error),
    );
  }
}
