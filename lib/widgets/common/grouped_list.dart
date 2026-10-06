import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'glass_card.dart';

/// Rows that belong together, in one card with a hairline between them.
///
/// A list drawn as one card per row is a stack of boxes: the eye reads the
/// boxes before it reads what is in them. One card holding its rows reads as
/// one list, which is what it is.
class GroupedCard extends StatelessWidget {
  const GroupedCard({
    super.key,
    required this.children,
    this.dividerIndent = 66,
  });

  final List<Widget> children;

  /// Where each hairline starts. The default lines it up with the text of a
  /// [GroupedRow] that has a 40dp leading tile, leaving the tiles in a clean
  /// column of their own.
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final line = context.glass.hairline;
    return GlassCard(
      padding: EdgeInsets.zero,
      // A Material of its own: the card paints a background, and without one
      // a row's press highlight would be drawn underneath it.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var i = 0; i < children.length; i++) ...<Widget>[
              if (i != 0)
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: dividerIndent,
                  color: line,
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// One row of a [GroupedCard]: something at the start, a name with a line
/// under it, and something at the end. The whole row is the tap target and
/// darkens under the finger.
class GroupedRow extends StatelessWidget {
  const GroupedRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
  });

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = ConstrainedBox(
      // Never less than a comfortable touch target, however little is in it.
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading!,
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DefaultTextStyle.merge(
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: title,
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    DefaultTextStyle.merge(
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );
    if (onTap == null && onLongPress == null) return row;
    return InkWell(onTap: onTap, onLongPress: onLongPress, child: row);
  }
}

/// A row of a [GroupedCard] with a layout of its own.
///
/// [GroupedRow] is the usual row. This is for the ones that are not a name,
/// a caption and an amount (a row ending in a button, a row with a picture):
/// they bring their own contents and get the same edges, the same height to
/// touch and the same answer to a press.
class CardRow extends StatelessWidget {
  const CardRow({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: padding,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          heightFactor: 1,
          child: child,
        ),
      ),
    );
    if (onTap == null && onLongPress == null) return row;
    return InkWell(onTap: onTap, onLongPress: onLongPress, child: row);
  }
}

/// The small tinted square at the start of a row, holding an icon or a
/// letter. One size, one corner and one strength of tint wherever it is used.
class LeadingTile extends StatelessWidget {
  const LeadingTile({super.key, required this.color, this.icon, this.letter})
    : assert(icon != null || letter != null);

  /// A tile showing the first letter of [name], for a person or a shop.
  LeadingTile.initial({super.key, required this.color, required String name})
    : icon = null,
      letter = name.trim().isEmpty
          ? '?'
          : name.trim().substring(0, 1).toUpperCase();

  final Color color;
  final IconData? icon;
  final String? letter;

  static const double size = 40;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: icon != null
            ? Icon(icon, color: color, size: 20)
            : Text(
                letter!,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: color),
              ),
      ),
    );
  }
}

/// The amount at the end of a row, with an optional line under it.
class TrailingAmount extends StatelessWidget {
  const TrailingAmount({
    super.key,
    required this.text,
    this.color,
    this.caption,
    this.captionColor,
  });

  final String text;
  final Color? color;
  final String? caption;
  final Color? captionColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            color: color,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        if (caption != null && caption!.isNotEmpty)
          Text(
            caption!,
            style: theme.textTheme.labelSmall?.copyWith(color: captionColor),
          ),
      ],
    );
  }
}

/// The small heading over a group of rows.
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: context.glass.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
