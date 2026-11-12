import 'package:flutter/material.dart';
import 'package:liyu_social/core/theme/app_theme.dart';

/// Constrains a column of content on wide screens without changing anything on
/// a phone.
///
/// The app is designed for a 5-inch handset first, but it also runs on web and
/// tablets, where an unconstrained feed becomes unreadable line lengths. This
/// keeps the measure fixed and the canvas pure.
class ContentShell extends StatelessWidget {
  const ContentShell({
    required this.child,
    this.maxWidth = 560,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.l),
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// Page title row with an optional trailing control, used above lists in the
/// tabs that have no app bar of their own.
class PageHeader extends StatelessWidget {
  const PageHeader({required this.title, this.subtitle, this.trailing, super.key});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.l, AppSpacing.s, AppSpacing.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: text.bodySmall),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A hairline between list rows. One pixel, no shadow, no inset by default.
class SectionDivider extends StatelessWidget {
  const SectionDivider({this.indent = 0, super.key});

  final double indent;

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: EdgeInsets.only(left: indent),
    color: Theme.of(context).colorScheme.outline,
  );
}

/// Section heading with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.trailing, this.padding, this.raised = false, super.key});

  final String title;
  final Widget? trailing;
  final EdgeInsets? padding;

  /// True for a section that opens a list, false for one below it.
  final bool raised;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding ??
        EdgeInsets.fromLTRB(AppSpacing.l, raised ? AppSpacing.xl : AppSpacing.m, AppSpacing.l, AppSpacing.s),
    child: Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        if (trailing != null) trailing!,
      ],
    ),
  );
}
