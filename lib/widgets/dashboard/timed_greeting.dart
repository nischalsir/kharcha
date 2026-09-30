import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n/app_l10n.dart';

/// The time-of-day greeting on the Home header.
///
/// It used to be a plain `Text` read once per build, so it sat there saying
/// "Good morning" for the rest of the session — even at 6pm. This owns the
/// clock, plays the correct greeting, then fades itself out so the user's name
/// and balance are what they actually look at.
class TimedGreeting extends StatefulWidget {
  const TimedGreeting({super.key, this.style});

  final TextStyle? style;

  /// How long the greeting stays fully visible before fading away.
  static const Duration hold = Duration(seconds: 4);

  /// How often the clock is re-read, so a screen left open still crosses from
  /// morning to afternoon to evening.
  static const Duration tick = Duration(seconds: 30);

  @override
  State<TimedGreeting> createState() => _TimedGreetingState();
}

class _TimedGreetingState extends State<TimedGreeting>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  Timer? _clock;
  Timer? _hide;
  String _text = '';
  bool _nepali = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(TimedGreeting.tick, (_) => _syncClock());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      // Honour reduced-motion by snapping instead of fading, but still let the
      // greeting leave so it stops sitting in the header.
      _controller.duration = Duration.zero;
    }
    // The language lives in an inherited widget, so it can only be read from
    // here (or build) — never from initState or a timer. Capture it, and keep
    // resolving the greeting from the captured value afterwards.
    _nepali = L10n.isNepali(context);
    final bool first = !_started;
    final String next = _greeting();
    if (first || next != _text) _text = next;
    if (first) {
      _started = true;
      _play();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _hide?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _syncClock() {
    if (!mounted) return;
    final next = _greeting();
    if (next == _text) return;
    // A new time of day earns the greeting again.
    setState(() => _text = next);
    _play();
  }

  String _greeting() =>
      L10n.timeGreetingFor(hour: DateTime.now().hour, nepali: _nepali);

  /// Fade in, hold, then fade out and stay hidden.
  void _play() {
    _hide?.cancel();
    _controller.forward(from: 0);
    _hide = Timer(TimedGreeting.hold, () {
      if (mounted) _controller.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Text(
        _text,
        style: widget.style ?? Theme.of(context).textTheme.headlineMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
