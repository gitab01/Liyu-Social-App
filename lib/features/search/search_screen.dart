import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/feature_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/core/widgets/layout.dart';
import 'package:liyu_social/core/widgets/state_views.dart';
import 'package:liyu_social/domain/models/user.dart';
import 'package:liyu_social/features/profile/widgets/follow_button.dart';

/// Find people, and start the two actions a profile card offers.
///
/// Search is by display name only. A real index would need a server-side text
/// scan, and faking it client-side over a whole collection is exactly the
/// unbounded read this app is built to avoid — so the field says what it does
/// and the results list stays bounded.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final needle = _query.text.trim();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: t.search,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: needle.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: t.retry,
                    onPressed: () => setState(_query.clear),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: needle.isEmpty
                ? _Discover(people: ref.watch(suggestionsProvider).valueOrNull ?? const <UserProfile>[])
                : _Results(query: needle),
          ),
        ],
      ),
    );
  }
}

/// The empty state is the discovery rail, not a message.
class _Discover extends StatelessWidget {
  const _Discover({required this.people});

  final List<UserProfile> people;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    if (people.isEmpty) return EmptyState(title: t.suggestionsForYou, icon: Icons.person_search_outlined);
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        SectionHeader(title: t.suggestionsForYou),
        for (final person in people) PersonTile(person: person),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final found = ref.watch(peopleSearchProvider(query));

    return found.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => FailureView(
        error: error,
        onRetry: () => ref.invalidate(peopleSearchProvider(query)),
      ),
      data: (people) {
        if (people.isEmpty) {
          return EmptyState(
            title: t.nothingNewHere,
            detail: query,
            icon: Icons.person_search_outlined,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          itemCount: people.length,
          separatorBuilder: (_, __) => const SectionDivider(),
          itemBuilder: (context, index) => PersonTile(person: people[index]),
        );
      },
    );
  }
}
