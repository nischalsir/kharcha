import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/app_theme.dart';
import '../../models/financial_summary.dart';
import '../../services/flamey_controller.dart';
import 'flame_mascot.dart';
import 'flamey_view.dart';
import 'glass_card.dart';
import 'pressable_scale.dart';

/// Flamey plus what is on its mind, shown at the top-right of the Total
/// Balance card.
///
/// Flamey itself is alive here: tap it, press and hold it or swipe across it
/// and it reacts (see [FlameyView]). The mood line is a thought: a bubble
/// that drifts out of Flamey, stays for [thoughtShown], goes, and comes back
/// after [thoughtGap]. Something Flamey says (see [FlameyController.message])
/// takes the bubble for as long as it is being said. Tapping the bubble opens
/// what the mood means.
///
/// The badge listens to the [FlameyController] on its own, so a line coming
/// or going rebuilds this badge and nothing else on the page.
class AiMoodBadge extends StatefulWidget {
  const AiMoodBadge({
    super.key,
    required this.mood,
    this.thoughtShown = const Duration(seconds: 6),
    this.thoughtGap = const Duration(seconds: 10),
  });

  final AiMood? mood;

  /// How long the thought stays before it goes.
  final Duration thoughtShown;

  /// How long Flamey is quiet before the thought comes back.
  final Duration thoughtGap;

  @override
  State<AiMoodBadge> createState() => _AiMoodBadgeState();
}

class _AiMoodBadgeState extends State<AiMoodBadge> {
  FlameyController? _controller;
  Timer? _timer;

  /// Whether the mood is being thought right now, or Flamey is between
  /// thoughts.
  bool _thinking = true;

  /// The line Flamey is saying, which is shown whatever [_thinking] is.
  String? _said;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.thoughtShown, _rest);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = FlameyController.maybeOf(context);
    if (identical(controller, _controller)) return;
    _controller?.removeListener(_onFlamey);
    _controller = controller?..addListener(_onFlamey);
    _said = controller?.message;
    if (_said != null) _timer?.cancel();
  }

  @override
  void didUpdateWidget(AiMoodBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new mood is a new thought: it is shown now, not at the next turn.
    if (oldWidget.mood?.label != widget.mood?.label && _said == null) {
      _think();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.removeListener(_onFlamey);
    super.dispose();
  }

  void _onFlamey() {
    final said = _controller?.message;
    if (said == _said || !mounted) return;
    setState(() => _said = said);
    if (said != null) {
      // The line stays for as long as the controller holds it.
      _timer?.cancel();
    } else {
      _rest();
    }
  }

  void _think() {
    _timer?.cancel();
    if (!mounted) return;
    setState(() => _thinking = true);
    _timer = Timer(widget.thoughtShown, _rest);
  }

  void _rest() {
    _timer?.cancel();
    if (!mounted) return;
    setState(() => _thinking = false);
    _timer = Timer(widget.thoughtGap, _think);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final current = widget.mood;

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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                // The thought going out leaves quickly, so two are never
                // read at once.
                reverseDuration: const Duration(milliseconds: 160),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerRight,
                  children: <Widget>[...previous, ?current],
                ),
                // It grows out of Flamey, on its right, and shrinks back in.
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    alignment: Alignment.centerRight,
                    scale: Tween<double>(begin: 0.6, end: 1).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: AppMotion.emphasized,
                        reverseCurve: Curves.easeIn,
                      ),
                    ),
                    child: child,
                  ),
                ),
                child: _thought(context),
              ),
            ),
            // A touch on Flamey between thoughts brings the thought back,
            // so what the mood means is never out of reach: the bubble is
            // what opens it. A Listener, so Flamey still gets the touch and
            // reacts to it as it always does.
            Listener(
              key: const ValueKey<String>('flamey-touch'),
              onPointerUp: (_) {
                if (!_thinking && _said == null) _think();
              },
              child: FlameyView(mood: current, size: 40),
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
    );
  }

  /// The bubble and the two small ones trailing from it to Flamey, or nothing
  /// while Flamey is between thoughts.
  Widget _thought(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.mood;
    final said = _said;
    if (said == null && (current == null || !_thinking)) {
      return const SizedBox.shrink(key: ValueKey<String>('flamey-no-thought'));
    }
    final color = current?.color(context) ?? theme.colorScheme.primary;
    // A plain, soft bubble that stands off the card: white on the light
    // card, a lighter grey on the dark one, with a faint shadow under it.
    // The mood's colour is kept for the words.
    final dark = theme.brightness == Brightness.dark;
    final fill = dark
        ? theme.colorScheme.surfaceContainerHighest
        : Colors.white;
    final shadow = <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.30 : 0.10),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ];

    // A small round one of the same stuff as the bubble, lower as it nears
    // Flamey: the trail that makes a bubble a thought.
    Widget puff(double size, double dy) => Transform.translate(
      offset: Offset(0, dy),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          boxShadow: shadow,
        ),
      ),
    );

    return Row(
      key: ValueKey<String>(said ?? current!.label),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: PressableScale(
            onTap: current == null ? null : () => _showMood(context, current),
            // Lifted a little above Flamey, with the trail coming down to
            // it.
            child: Transform.translate(
              offset: const Offset(0, -4),
              child: Container(
                key: const ValueKey<String>('flamey-thought-bubble'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                // Wide enough for a short line over two rows, never so wide
                // that it pushes the card's own heading out.
                constraints: const BoxConstraints(maxWidth: 164),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: shadow,
                ),
                child: Builder(
                  builder: (context) => said != null
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
            ),
          ),
        ),
        // Smaller and lower towards Flamey, the way a thought trails down
        // to the head it came from.
        const SizedBox(width: 3),
        puff(8, 7),
        const SizedBox(width: 3),
        puff(5, 13),
        const SizedBox(width: 4),
      ],
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
