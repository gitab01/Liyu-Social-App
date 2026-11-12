import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/providers/feature_providers.dart';
import 'package:liyu_social/domain/models/conversation.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/domain/models/media.dart';
import 'package:liyu_social/domain/models/post.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';
import 'package:liyu_social/domain/services/mention_parser.dart';
import 'package:liyu_social/features/composer/application/mention_handles.dart';

/// Where one attachment is in the pipeline. `preparing` is on-device work, so it
/// happens even with no connection at all.
enum MediaPhase { preparing, ready, uploading, uploaded, failed }

class ComposerItem {
  const ComposerItem({
    required this.localId,
    required this.source,
    this.prepared,
    this.uploaded,
    this.phase = MediaPhase.preparing,
    this.progress = 0,
    this.error,
  });

  final String localId;
  final SourceFile source;
  final PreparedMedia? prepared;
  final MediaRef? uploaded;
  final MediaPhase phase;
  final double progress;
  final String? error;

  int? get savedBytes => prepared == null ? null : prepared!.originalBytes - prepared!.bytes.length;

  double get savedPercent {
    final original = prepared?.originalBytes ?? 0;
    if (original <= 0) return 0;
    return (1 - prepared!.bytes.length / original).clamp(0, 1).toDouble();
  }

  ComposerItem copyWith({PreparedMedia? prepared, MediaRef? uploaded, MediaPhase? phase, double? progress, String? error}) =>
      ComposerItem(
        localId: localId,
        source: source,
        prepared: prepared ?? this.prepared,
        uploaded: uploaded ?? this.uploaded,
        phase: phase ?? this.phase,
        progress: progress ?? this.progress,
        error: error ?? this.error,
      );
}

class ComposerState {
  const ComposerState({
    this.items = const [],
    this.caption = '',
    this.audience = Audience.everyone,
    this.publishing = false,
    this.error,
  });

  final List<ComposerItem> items;
  final String caption;
  final Audience audience;
  final bool publishing;
  final String? error;

  bool get canPublish => caption.trim().isNotEmpty || items.any((i) => i.phase != MediaPhase.preparing);

  bool get anyUploading => items.any((i) => i.phase == MediaPhase.uploading || i.phase == MediaPhase.preparing);

  ComposerItem? find(String localId) => items.where((i) => i.localId == localId).firstOrNull;

  ComposerState copyWith({List<ComposerItem>? items, String? caption, Audience? audience, bool? publishing, String? error}) =>
      ComposerState(
        items: items ?? this.items,
        caption: caption ?? this.caption,
        audience: audience ?? this.audience,
        publishing: publishing ?? this.publishing,
        error: error,
      );
}

/// Drives publish: compress on-device, upload, then write the document with the
/// references that came back.
///
/// The order matters for the data story — the document is written last so a
/// post never points at a media object that does not exist. When the connection
/// is down, the upload goes through the write queue and this returns only once
/// it has actually landed, which is why the composer can say "will publish when
/// you reconnect" rather than pretending.
class ComposerController extends AutoDisposeNotifier<ComposerState> {
  @override
  ComposerState build() => const ComposerState();

  void setCaption(String value) => state = state.copyWith(caption: value);

  void setAudience(Audience value) => state = state.copyWith(audience: value);

  Future<void> addFiles(List<SourceFile> files) async {
    for (final file in files) {
      final localId = 'local-${DateTime.now().microsecondsSinceEpoch}-${files.indexOf(file)}';
      state = state.copyWith(items: [...state.items, ComposerItem(localId: localId, source: file)]);
      await _prepare(localId);
    }
  }

  Future<void> _prepare(String localId) async {
    final item = state.find(localId);
    if (item == null) return;
    try {
      final prepared = await ref.read(mediaRepositoryProvider).prepare(item.source);
      _replace(item.copyWith(prepared: prepared, phase: MediaPhase.ready));
    } on Object catch (error) {
      _replace(item.copyWith(phase: MediaPhase.failed, error: error.toString()));
    }
  }

  void removeItem(String localId) {
    state = state.copyWith(items: state.items.where((i) => i.localId != localId).toList());
  }

  void _replace(ComposerItem item) {
    state = state.copyWith(items: [for (final i in state.items) if (i.localId == item.localId) item else i]);
  }

  /// Returns the published post, or null when the composer refused to start.
  Future<Post?> publish() async {
    if (state.publishing || !state.canPublish) return null;
    final author = _authorRef();
    if (author == null) {
      state = state.copyWith(error: 'No signed-in account');
      return null;
    }

    state = state.copyWith(publishing: true);
    try {
      final refs = <MediaRef>[];
      for (final item in state.items) {
        refs.add(await _upload(item));
      }

      final post = await ref.read(feedRepositoryProvider).publish(
        author: author,
        media: refs,
        caption: state.caption.trim(),
        audience: state.audience,
        mentions: mentionUidsIn(state.caption, handleToUid: _handleIndex()),
      );

      state = const ComposerState();
      return post;
    } on Object catch (error) {
      state = state.copyWith(publishing: false, error: error.toString());
      rethrow;
    }
  }

  Future<MediaRef> _upload(ComposerItem item) async {
    if (item.uploaded != null) return item.uploaded!;
    final prepared = item.prepared;
    if (prepared == null) throw StateError('media was not prepared');
    final author = _authorRef();
    if (author == null) throw StateError('no signed-in account');

    _replace(item.copyWith(phase: MediaPhase.uploading));
    final reference = await ref.read(mediaRepositoryProvider).upload(
      ownerUid: author.uid,
      prepared: prepared,
      purpose: MediaPurpose.post,
      onProgress: (progress) => _replace(item.copyWith(phase: MediaPhase.uploading, progress: progress)),
    );
    _replace(item.copyWith(uploaded: reference, phase: MediaPhase.uploaded, progress: 1));
    return reference;
  }

  /// A story takes a single already-chosen file and goes through the same
  /// compress-then-upload path, so the rail and the composer cost the same.
  Future<void> publishStory(SourceFile file, {String caption = ''}) async {
    final author = _authorRef();
    if (author == null) throw StateError('no signed-in account');

    final prepared = await ref.read(mediaRepositoryProvider).prepare(file);
    final uploaded = await ref.read(mediaRepositoryProvider).upload(
      ownerUid: author.uid,
      prepared: prepared,
      purpose: MediaPurpose.story,
    );
    await ref.read(storyRepositoryProvider).publish(
      author: author,
      media: uploaded,
      caption: caption,
    );
  }

  UserProfileRef? _authorRef() {
    final user = ref.read(currentUserProvider).valueOrNull ?? ref.read(signedInUserProvider).valueOrNull;
    if (user == null) return null;
    return UserProfileRef(uid: user.uid, displayName: user.displayName, photoUrl: user.photoUrl);
  }

  /// Only accounts the author can reach are mentionable, which keeps a typed
  /// `@name` from resolving to a stranger the picker never offered.
  Map<String, String> _handleIndex() => handleIndexFrom(
    suggestions: ref.read(suggestionsProvider).valueOrNull ?? const [],
    conversations: ref.read(inboxProvider).valueOrNull ?? const [],
  );
}

final composerProvider = NotifierProvider.autoDispose<ComposerController, ComposerState>(
  ComposerController.new,
);
