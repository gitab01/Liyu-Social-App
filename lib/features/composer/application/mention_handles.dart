import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/user.dart';

/// The accounts a written `@handle` can resolve to.
///
/// Only people already on the device — suggestions and existing conversations —
/// are mentionable. That is not a limitation of the parser, it is the same
/// constraint the autocomplete UI enforces: a name the author could never have
/// picked should not silently notify a stranger.
///
/// Both the post composer and the comment box call this, so a mention resolves
/// the same way from either surface.
Map<String, String> handleIndexFrom({
  required List<UserProfile> suggestions,
  required List<Conversation> conversations,
}) {
  final people = <UserProfile>[
    ...suggestions,
    for (final conversation in conversations)
      UserProfile(
        uid: conversation.peer.uid,
        displayName: conversation.peer.displayName,
        photoUrl: conversation.peer.photoUrl,
      ),
  ];
  return {
    for (final person in people)
      if (person.uid.isNotEmpty && person.displayName.isNotEmpty)
        handleOf(person.displayName): person.uid,
  };
}

/// Display name as it is typed after the `@`: lowercase, spaces underscored.
String handleOf(String name) => name.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
