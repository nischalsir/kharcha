import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n/app_l10n.dart';

/// The time-of-day greeting on the Home header.
///
/// Updates automatically when the time of day changes (morning/afternoon/
/// evening/night). Stays visible permanently.
class TimedGreeting extends StatefulWidget {
  const TimedGreeting({super.key, this.style});

  final TextStyle? style;

  /// How often the clock is re-read, so a screen left open still crosses from
  /// morning to afternoon to evening.
  static const Duration tick = Duration(seconds: 30);

  @override
  State<TimedGreeting> createState() => _TimedGreetingState();
}

class _TimedGreetingState extends State<TimedGreeting> {
  Timer? _clock;
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
    _nepali = L10n.isNepali(context);
    final bool first = !_started;
    final String next = _greeting();
    if (first || next != _text) _text = next;
    if (first) _started = true;
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _syncClock() {
    if (!mounted) return;
    final next = _greeting();
    if (next == _text) return;
    setState(() => _text = next);
  }

  String _greeting() =>
      L10n.timeGreetingFor(hour: DateTime.now().hour, nepali: _nepali);

  @override
  Widget build(BuildContext context) {
    return Text(
      _text,
      style: widget.style ?? Theme.of(context).textTheme.headlineMedium,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
