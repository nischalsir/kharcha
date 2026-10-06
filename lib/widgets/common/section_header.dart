import 'package:flutter/material.dart';

import 'pressable_scale.dart';

/// The heading over a section of a page, with an optional link at its end.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(4, 20, 4, 8),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            PressableScale(
              onTap: onAction,
              // Room around the words, so the link is as easy to hit as a
              // button without looking like one.
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
                child: Text(
                  actionLabel!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
