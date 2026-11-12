import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/feature_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/core/widgets/layout.dart';
import 'package:liyu_social/core/widgets/state_views.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';
import 'package:liyu_social/features/profile/widgets/follow_button.dart';

/// Followers or following, as a list of people you can act on.
///
/// The read goes through the same connection stream the profile counts come
/// from, so this list and the number that opened it cannot disagree for long.
class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({required this.uid, required this.kind, super.key});

  final String uid;
  final String kind;

  ConnectionKind get _parsed =>
      ConnectionKind.values.firstWhere((k) => k.name == kind, orElse: () => ConnectionKind.followers);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final title = _parsed == ConnectionKind.followers ? t.followers : t.following;
    final people = ref.watch(connectionsProvider((uid: uid, kind: _parsed)));

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: people.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => FailureView(
          error: error,
          onRetry: () => ref.invalidate(connectionsProvider((uid: uid, kind: _parsed))),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              title: t.nothingNewHere,
              icon: Icons.person_outline,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SectionDivider(indent: 72),
            itemBuilder: (context, index) => PersonTile(person: list[index]),
          );
        },
      ),
    );
  }
}
