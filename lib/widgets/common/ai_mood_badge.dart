import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/theme/app_theme.dart';
import '../../models/financial_summary.dart';
import '../../services/flamey_controller.dart';
import 'flame_mascot.dart';
import 'flamey_view.dart';
import 'glass_card.dart';
import 'pressable_scale.dart';

/// Flamey plus the current mood line, shown at the top-right of the Total
/// Balance card.
///
/// Flamey itself is alive here: tap it, press and hold it or swipe across it
/// and it reacts (see [FlameyView]). Now and then it says something, which
/// appears in the pill beside it. Tapping the pill opens what the mood means.
///
/// The pill and the mascot listen to the [FlameyController] on their own, so
/// an expression changing rebuilds this badge and nothing else on the page.
class AiMoodBadge extends StatelessWidget {
  const AiMoodBadge({super.key, required this.mood});

  final AiMood? mood;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final current = mood;
    final controller = FlameyController.maybeOf(context);

    Widget pill(String? said) {
      if (current == null && said == null) return const SizedBox.shrink();
      final color = current?.color(context) ?? theme.colorScheme.primary;
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        // The line going out leaves quickly, so two are never read at once.
        reverseDuration: const Duration(milliseconds: 80),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerRight,
          children: <Widget>[...previous, ?current],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            alignment: Alignment.centerRight,
            scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: PressableScale(
          key: ValueKey<String>(said ?? current!.label),
          onTap: current == null ? null : () => _showMood(context, current),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            // Wide enough for a short line over two rows, never so wide that
            // it pushes the card's own heading out.
            constraints: const BoxConstraints(maxWidth: 168),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(said == null ? 999 : 12),
            ),
            child: said != null
                ? Text(
                    said,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        current!.emoji,
                        style: const TextStyle(fontSize: 11),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          current.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: current == null
          ? AppInfo.assistantName
          : '${AppInfo.assistantName}: ${current.label}',
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Flexible(
              child: controller == null
                  ? pill(null)
                  : ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => pill(controller.message),
                    ),
            ),
            FlameyView(mood: current, size: 40),
            if (current == null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  AppInfo.assistantName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: glass.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showMood(BuildContext context, AiMood mood) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: GlassCard(
            strong: true,
            glow: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    FlameMascot(
                      face: mood.face,
                      tone: mood.tone,
                      energy: mood.energy,
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${mood.emoji}  ${mood.label}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: mood.color(sheetContext),
                            ),
                          ),
                          if (mood.weatherLabel != null)
                            Text(
                              mood.weatherLabel!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: sheetContext.glass.textTertiary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  mood.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: sheetContext.glass.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
