import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:liyu_social/core/theme/app_theme.dart';

/// Circular avatar: a photo when there is one, otherwise initials on a flat
/// color chosen from the uid, so the same person is always the same color.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    required this.name,
    this.photoUrl,
    this.size = 40,
    this.storyRing,
    super.key,
  });

  final String name;
  final String? photoUrl;
  final double size;

  /// null = no ring, false = unseen story ring, true = seen.
  final bool? storyRing;

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(shape: BoxShape.circle, color: _tintFor(name, Theme.of(context))),
      child: _content(context),
    );

    if (storyRing == null) return circle;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: storyRing! ? scheme.outline : scheme.primary,
            width: 2.5,
          ),
        ),
        child: Padding(padding: const EdgeInsets.all(2), child: circle),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final url = photoUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _initials(context),
      );
    }
    return _initials(context);
  }

  Widget _initials(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        initialsOf(name),
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return _firstGrapheme(parts.first).toUpperCase();
  return (_firstGrapheme(parts.first) + _firstGrapheme(parts[1])).toUpperCase();
}

/// Takes one *grapheme cluster*, not one code unit. Ge'ez letters and any
/// combining marks must not be sliced in half.
String _firstGrapheme(String value) {
  final runes = value.runes.toList();
  return runes.isEmpty ? '?' : String.fromCharCode(runes.first);
}

Color _tintFor(String name, ThemeData theme) {
  final isDark = theme.brightness == Brightness.dark;
  final tints = isDark
      ? const [Color(0xFF1F2A24), Color(0xFF2A2519), Color(0xFF1E2530), Color(0xFF2B1F24)]
      : const [Color(0xFFE7EEE9), Color(0xFFF1EADA), Color(0xFFE5EAF1), Color(0xFFF2E6E8)];
  var hash = 7;
  for (final unit in name.codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  return tints[hash % tints.length];
}

/// One-line label with the count it belongs to, used across profile and stats.
class MetaText extends StatelessWidget {
  const MetaText({required this.text, this.emphasized = false, super.key});

  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Text(
      this.text,
      style: emphasized
          ? text.labelMedium?.copyWith(color: scheme.onSurface)
          : text.bodySmall?.copyWith(color: scheme.onSurface.withValues(alpha: 0.65)),
    );
  }
}

/// Small flat tag: backend mode, delivery state, audience. Never a chip with a
/// shadow — these appear dozens of times per screen.
class TagLabel extends StatelessWidget {
  const TagLabel({required this.text, this.color, this.icon, super.key});

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = color ?? scheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tone),
            const SizedBox(width: 4),
          ],
          Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tone)),
        ],
      ),
    );
  }
}
