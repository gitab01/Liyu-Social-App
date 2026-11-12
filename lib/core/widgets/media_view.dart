import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/domain/models/media.dart';

/// Whether to ask for the small rendition or the full one.
///
/// Lists always pass [thumbnail]: loading full-resolution media in a scrollable
/// is the single largest avoidable data cost in a social app.
enum MediaQuality { thumbnail, full }

/// Renders a [MediaRef] whatever its state: a remote url, bytes produced on this
/// device, or neither.
///
/// The last case matters because a post document can arrive before its media
/// does, and offline the media may never arrive. Painting a deterministic
/// placeholder keyed on the media id keeps scroll geometry stable and the row
/// recognizable, instead of showing a spinner or a broken image.
class MediaView extends ConsumerWidget {
  const MediaView({
    required this.media,
    this.quality = MediaQuality.thumbnail,
    this.fit = BoxFit.cover,
    super.key,
  });

  final MediaRef media;
  final MediaQuality quality;
  final BoxFit fit;

  String get _localKey => '${quality.name}:${media.id}';

  String? get _url => switch (quality) {
    MediaQuality.thumbnail => media.thumbUrl ?? media.fullUrl,
    MediaQuality.full => media.fullUrl ?? media.thumbUrl,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (media.uploadFailed) return _BrokenMedia(id: media.id);

    final url = _url;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, __) => GeneratedMedia(id: media.id),
        errorWidget: (_, __, ___) => GeneratedMedia(id: media.id),
      );
    }

    final bytes = ref.watch(mediaStoreProvider).bytes(_localKey);
    if (bytes != null) {
      return Image.memory(bytes, fit: fit, gaplessPlayback: true);
    }

    return GeneratedMedia(id: media.id);
  }
}

/// Flat, deterministic artwork standing in for media that has not resolved.
/// The same id always paints the same composition, so a feed row does not
/// repaint differently on every scroll.
class GeneratedMedia extends StatelessWidget {
  const GeneratedMedia({required this.id, this.compact = false, super.key});

  final String id;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = _paletteFor(id, scheme);
    return CustomPaint(
      painter: _GeneratedPainter(seed: _seedOf(id), colors: palette),
      size: Size.infinite,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: palette.onWhite ? Colors.black26 : Colors.white30,
          size: compact ? 20 : 32,
        ),
      ),
    );
  }
}

class _Palette {
  const _Palette({required this.field, required this.shape, required this.accent, required this.onWhite});

  final Color field;
  final Color shape;
  final Color accent;
  final bool onWhite;
}

_Palette _paletteFor(String id, ColorScheme scheme) {
  final seed = _seedOf(id);
  // Flat neutral fields only: no gradients, and the tint stays inside this tile
  // rather than leaking onto the page behind it.
  final fields = scheme.brightness == Brightness.dark
      ? const [Color(0xFF1A1A1A), Color(0xFF17201B), Color(0xFF201C15)]
      : const [Color(0xFFF0F0EC), Color(0xFFE9EFEA), Color(0xFFF2EDE1)];
  final shapes = scheme.brightness == Brightness.dark
      ? const [Color(0xFF2E4B3B), Color(0xFF4A4227), Color(0xFF37414B)]
      : const [Color(0xFFD6E2D8), Color(0xFFE6DCC2), Color(0xFFD8DEE6)];
  final i = seed % fields.length;
  return _Palette(
    field: fields[i],
    shape: shapes[i],
    accent: scheme.primary,
    onWhite: scheme.brightness == Brightness.light,
  );
}

int _seedOf(String id) {
  if (id.isEmpty) return 0;
  var hash = 17;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  return hash;
}

class _GeneratedPainter extends CustomPainter {
  const _GeneratedPainter({required this.seed, required this.colors});

  final int seed;
  final _Palette colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = colors.field);

    final w = size.width, h = size.height;
    final variant = seed % 4;
    final fill = Paint()..color = colors.shape;
    final accent = Paint()
      ..color = colors.accent.withValues(alpha: 0.5)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = (w / 28).clamp(1.5, 4);

    switch (variant) {
      case 0:
        canvas.drawCircle(Offset(w * 0.5, h * 0.55), w * 0.26, fill);
        canvas.drawLine(Offset(0, h * 0.8), Offset(w, h * 0.8), accent);
      case 1:
        final path = Path()
          ..moveTo(0, h)
          ..lineTo(w * 0.5, h * 0.35)
          ..lineTo(w, h)
          ..close();
        canvas.drawPath(path, fill);
      case 2:
        canvas.drawRect(Rect.fromLTWH(w * 0.12, h * 0.2, w * 0.5, h * 0.5), fill);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.45, h * 0.4, w * 0.42, h * 0.42),
            Radius.circular(w * 0.06),
          ),
          accent,
        );
      default:
        canvas.drawRect(Rect.fromLTWH(0, h * 0.62, w, h * 0.38), fill);
        canvas.drawCircle(Offset(w * 0.22, h * 0.3), w * 0.12, accent);
    }
  }

  @override
  bool shouldRepaint(_GeneratedPainter old) => old.seed != seed || old.colors.field != colors.field;
}

/// Shown where an upload ended in failure, so the row explains itself instead
/// of silently becoming a placeholder.
class _BrokenMedia extends StatelessWidget {
  const _BrokenMedia({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, color: scheme.error),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Media did not upload',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
