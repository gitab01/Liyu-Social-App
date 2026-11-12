import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/core/utils/formatters.dart';
import 'package:liyu_social/core/utils/media_picker.dart';
import 'package:liyu_social/core/widgets/layout.dart';
import 'package:liyu_social/core/widgets/media_view.dart';
import 'package:liyu_social/core/widgets/state_views.dart';
import 'package:liyu_social/core/widgets/user_avatar.dart';
import 'package:liyu_social/domain/models/enums.dart';
import 'package:liyu_social/features/composer/application/composer_controller.dart';

/// The composer: caption, audience, and the media pipeline made visible.
///
/// Showing compression is the point of this screen. A metered user cannot see a
/// data saving they are told about, so each attachment reports the bytes it
/// started as, the bytes it will upload, and the difference — and the publish
/// button stays disabled until the uploads it is about to do have actually
/// finished or genuinely failed.
class ComposerScreen extends ConsumerStatefulWidget {
  const ComposerScreen({super.key});

  @override
  ConsumerState<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends ConsumerState<ComposerScreen> {
  final _caption = TextEditingController();

  @override
  void initState() {
    super.initState();
    _caption.text = ref.read(composerProvider).caption;
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool fromCamera}) async {
    final files = fromCamera ? await pickCameraPhoto() : await pickGalleryImages();
    if (files.isEmpty) return;
    await ref.read(composerProvider.notifier).addFiles(files);
  }

  Future<void> _publish() async {
    final messenger = ScaffoldMessenger.of(context);
    final t = context.t;
    final before = ref.read(pendingWritesProvider).value;
    try {
      final post = await ref.read(composerProvider.notifier).publish();
      if (post == null) return;
      _caption.clear();
      final queuedWhileOffline = ref.read(pendingWritesProvider).value > before;
      messenger.showSnackBar(
        SnackBar(content: Text(queuedWhileOffline ? t.queuedForSync : t.postPublished)),
      );
      if (!mounted) return;
      // Leave the tab before the new post scrolls into a list the reader was
      // not looking at; the feed re-reads its head on the way back.
      context.go('/feed');
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final composer = ref.watch(composerProvider);
    final uploading = composer.anyUploading;
    final failed = composer.items.any((i) => i.phase == MediaPhase.failed);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.newPost),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: SingleChildScrollView(
              child: ContentShell(
                padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.m, AppSpacing.l, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _caption,
                      maxLines: 6,
                      minLines: 3,
                      maxLength: 500,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: t.whatsOnYourMind, border: InputBorder.none),
                      onChanged: (value) => ref.read(composerProvider.notifier).setCaption(value),
                    ),
                    SectionDivider(),
                    const SizedBox(height: AppSpacing.m),
                    _AudienceRow(
                      value: composer.audience,
                      onChanged: (value) => ref.read(composerProvider.notifier).setAudience(value),
                    ),
                    if (composer.items.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.l),
                      for (final item in composer.items) _AttachmentCard(item: item),
                    ],
                    const SizedBox(height: AppSpacing.l),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: uploading ? null : () => _pick(fromCamera: false),
                            icon: const Icon(Icons.image_outlined),
                            label: Text(t.gallery),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: uploading ? null : () => _pick(fromCamera: true),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: Text(t.camera),
                          ),
                        ),
                      ],
                    ),
                    if (failed) ...[
                      const SizedBox(height: AppSpacing.m),
                      Text(t.somethingWentWrong, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          _PublishBar(
            enabled: composer.canPublish && !uploading && !failed,
            busy: composer.publishing,
            onPublish: _publish,
          ),
        ],
      ),
    );
  }
}

/// Who can see this post. The choice is stored on the document, and the rules
/// enforce it on read — which is why it is offered here rather than in a menu
/// after publishing.
class _AudienceRow extends StatelessWidget {
  const _AudienceRow({required this.value, required this.onChanged});

  final Audience value;
  final ValueChanged<Audience> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        MetaText(text: t.audience),
        const SizedBox(width: AppSpacing.m),
        Expanded(
          child: SegmentedButton<Audience>(
            segments: [
              ButtonSegment(value: Audience.everyone, label: Text(t.everyone)),
              ButtonSegment(value: Audience.followers, label: Text(t.followersOnly)),
            ],
            selected: {value},
            onSelectionChanged: (selection) => onChanged(selection.first),
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
      ],
    );
  }
}

/// One attachment and exactly where it is in the pipeline.
///
/// The byte numbers are the honest ones: the original file size against what is
/// about to be uploaded, read off the prepared pair rather than estimated.
class _AttachmentCard extends ConsumerWidget {
  const _AttachmentCard({required this.item});

  final ComposerItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).languageCode;
    final prepared = item.prepared;
    final uploaded = item.uploaded;

    final label = switch (item.phase) {
      MediaPhase.preparing => t.compressing,
      MediaPhase.ready => null,
      MediaPhase.uploading => '${t.uploading} ${percent(item.progress)}',
      MediaPhase.uploaded => t.sent,
      MediaPhase.failed => t.failedToSend,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: ClipRect(
              child: uploaded != null
                  ? MediaView(media: uploaded, quality: MediaQuality.thumbnail)
                  : (prepared == null
                      ? ColoredBox(color: scheme.surface, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)))
                      : _PreparedThumb(item: item)),
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null) Text(label, style: text.titleSmall),
                if (prepared != null)
                  MetaText(
                    text: '${formatBytes(prepared.originalBytes, languageCode: locale)} → '
                        '${formatBytes(prepared.bytes.length, languageCode: locale)}',
                  ),
                if (item.savedBytes != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${t.savingData} ${formatBytes(item.savedBytes, languageCode: locale)}',
                      style: text.labelSmall?.copyWith(color: scheme.primary),
                    ),
                  ),
                if (item.error != null && item.phase == MediaPhase.failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(item.error!, style: text.bodySmall?.copyWith(color: scheme.error)),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => ref.read(composerProvider.notifier).removeItem(item.localId),
            icon: const Icon(Icons.close),
            tooltip: t.delete,
          ),
        ],
      ),
    );
  }
}

/// The thumbnail the pipeline produced on this device, before any upload exists
/// to point at. Painting the real bytes here is what keeps the preview honest
/// when there is no connection at all.
class _PreparedThumb extends StatelessWidget {
  const _PreparedThumb({required this.item});

  final ComposerItem item;

  @override
  Widget build(BuildContext context) {
    final prepared = item.prepared!;
    return Image.memory(
      prepared.thumbBytes,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: const Icon(Icons.image_outlined),
      ),
    );
  }
}

/// Publish, with the reason it is not available yet.
class _PublishBar extends ConsumerWidget {
  const _PublishBar({required this.enabled, required this.busy, required this.onPublish});

  final bool enabled;
  final bool busy;
  final Future<void> Function() onPublish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    final pending = ref.watch(pendingWritesProvider).value;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pending > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s),
                child: MetaText(text: '${t.offline}: $pending ${t.queuedForSync}'),
              ),
            FilledButton(
              onPressed: enabled && !busy ? onPublish : null,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(busy ? t.publishing : t.publish),
            ),
            if (!enabled)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s),
                child: Text(
                  t.required,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
