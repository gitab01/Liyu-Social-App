import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/feature_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/core/utils/formatters.dart';
import 'package:liyu_social/core/widgets/layout.dart';
import 'package:liyu_social/core/widgets/user_avatar.dart';
import 'package:liyu_social/domain/models/user.dart';
import 'package:liyu_social/features/profile/widgets/follow_button.dart';

/// People you do not follow yet, under the last feed page.
///
/// Placed at the end of the scroll rather than in a panel, because a reader who
/// has reached the bottom has consumed everything the graph currently offers —
/// an empty feed is a discovery problem, not a content problem.
class SuggestionStrip extends ConsumerWidget {
  const SuggestionStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(suggestionsProvider).valueOrNull ?? const <UserProfile>[];
    if (people.isEmpty) return const SizedBox.shrink();
    final t = context.t;
    final locale = Localizations.localeOf(context).languageCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionDivider(),
        SectionHeader(title: t.suggestionsForYou, raised: true),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
            itemCount: people.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.m),
            itemBuilder: (context, index) {
              final person = people[index];
              return _SuggestionCard(person: person, locale: locale);
            },
          ),
        ),
        const SizedBox(height: AppSpacing.l),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.person, required this.locale});

  final UserProfile person;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => context.push('/profile/${person.uid}'),
            child: UserAvatar(name: person.displayName, photoUrl: person.photoUrl, size: 64),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(person.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium),
          MetaText(text: '${compactCount(person.followersCount, languageCode: locale)} ${context.t.followers}'),
          const SizedBox(height: AppSpacing.s),
          FollowButton(target: person, compact: true),
        ],
      ),
    );
  }
}
