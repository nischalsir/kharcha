import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'glass_button.dart';
import 'primary_button.dart';

/// Shown where a list would be, when there is nothing in it yet: what is
/// missing, in a line, and the one thing that would put something there.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final hasAction = actionLabel != null && onAction != null;
    return _StateMessage(
      icon: icon,
      tint: context.glass.textSecondary,
      title: title,
      message: message,
      action: hasAction
          ? PrimaryButton(
              label: actionLabel!,
              onPressed: onAction,
              expanded: false,
            )
          : null,
    );
  }
}

/// Shown where content would be, when fetching it did not work. It is not an
/// empty state: nothing here says there is nothing, only that it could not
/// be reached, and it offers to try again.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.title,
    this.message,
    this.retryLabel,
    this.onRetry,
    this.icon = Icons.cloud_off_rounded,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final canRetry = retryLabel != null && onRetry != null;
    return _StateMessage(
      icon: icon,
      tint: context.glass.warning,
      title: title,
      message: message,
      action: canRetry
          ? GlassButton(
              label: retryLabel!,
              icon: Icons.refresh_rounded,
              compact: true,
              onPressed: onRetry,
            )
          : null,
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.tint,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Decoration: the title says the same thing in words.
            ExcludeSemantics(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 26, color: tint),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: theme.textTheme.labelLarge,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: glass.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
