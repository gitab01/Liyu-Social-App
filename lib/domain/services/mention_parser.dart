import 'package:liyu_social/domain/models/user.dart';

/// Extracts mentioned uids from free text.
///
/// Mentions are resolved at write time rather than in a Cloud Function, because
/// a Function would have to re-query the user collection for every `@handle` in
/// every post, comment and message. The client already has the candidates in
/// hand from the autocomplete it used to insert the text.
List<String> mentionUidsIn(String text, {Map<String, String> handleToUid = const {}}) {
  if (text.isEmpty || handleToUid.isEmpty) return const [];
  final handles = RegExp(r'@([\p{L}\p{N}_.]+)', unicode: true, multiLine: true)
      .allMatches(text)
      .map((m) => m.group(1)!.toLowerCase())
      .toSet();
  return [for (final handle in handles) if (handleToUid[handle] != null) handleToUid[handle]!];
}

/// Suggested handles, filtered by the fragment the author has typed so far.
List<UserProfile> mentionsMatching(String fragment, List<UserProfile> candidates, {int limit = 6}) {
  final needle = fragment.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  final matches = candidates.where(
    (u) => u.displayName.toLowerCase().contains(needle),
  );
  return matches.take(limit).toList();
}
