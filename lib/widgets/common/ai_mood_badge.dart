import '../../core/app_info.dart';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/financial_summary.dart';
import 'flame_mascot.dart';
import 'glass_card.dart';
import 'pressable_scale.dart';

/// The AI mascot plus its current mood line, shown at the top-right of the
/// Total Balance card.
///
/// Reacts visibly when the mood changes: the label colour animates to the new
/// tone and the mascot pops with a short scale bounce, so a transaction the
/// user just added is acknowledged without them having to tap anything.
class AiMoodBadge extends StatefulWidget {
  const AiMoodBadge({super.key, required this.mood});

  final AiMood? mood;

  @override
  State<AiMoodBadge> createState() => _AiMoodBadgeState();
}

class _AiMoodBadgeState extends State<AiMoodBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  late final Animation<double> _scale = TweenSequence<double>(
    <TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.28,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 42,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 1.28,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 58,
      ),
    ],
  ).animate(_pop);

  String? _lastSignature;

  @override
  void initState() {
    super.initState();
    _lastSignature = _signatureOf(widget.mood);
  }

  @override
  void didUpdateWidget(AiMoodBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _signatureOf(widget.mood);
    if (signature != _lastSignature) {
      _lastSignature = signature;
      if (widget.mood != null && !MediaQuery.disableAnimationsOf(context)) {
        _pop.forward(from: 0);
      }
    }
  }

  static String? _signatureOf(AiMood? mood) => mood == null
      ? null
      : '${mood.label}|${mood.face.name}|${mood.tone.name}|${mood.message}';

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final current = widget.mood;

    return Semantics(
      button: current != null,
      label: current == null
          ? AppInfo.assistantName
          : '${AppInfo.assistantName}: ${current.label}',
      child: PressableScale(
        onTap: current == null ? null : () => _showMood(context, current),
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              if (current != null)
                Flexible(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SizeTransition(
                        axis: Axis.horizontal,
                        sizeFactor: animation,
                        child: child,
                      ),
                    ),
                    child: Container(
                      key: ValueKey<String>(current.label),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: current.color(context).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            current.emoji,
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            current.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: current.color(context),
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ScaleTransition(
                scale: _scale,
                child: FlameMascot(
                  face: current?.face ?? MoodFace.calm,
                  tone: current?.tone ?? MoodTone.neutral,
                  energy: current?.energy,
                  size: 40,
                ),
              ),
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
