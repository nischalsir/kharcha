import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/financial_summary.dart';

/// Everything Flamey can look like. Each maps to one drawn face; see [face].
enum FlameyExpression {
  idle(MoodFace.calm),
  happy(MoodFace.happy),
  excited(MoodFace.excited),
  curious(MoodFace.curious),
  thinking(MoodFace.thinking),
  confused(MoodFace.confused),
  surprised(MoodFace.surprised),
  shocked(MoodFace.shocked),
  proud(MoodFace.proud),
  celebrating(MoodFace.party),
  sleepy(MoodFace.sleepy),
  bored(MoodFace.bored),
  playful(MoodFace.wink),
  teasing(MoodFace.teasing),
  roasting(MoodFace.roasting),
  worried(MoodFace.worried),
  sad(MoodFace.sad),
  error(MoodFace.dizzy),
  loading(MoodFace.loading),
  success(MoodFace.happy),
  moneySaving(MoodFace.love),
  overspending(MoodFace.grumpy),
  goalReached(MoodFace.starstruck);

  const FlameyExpression(this.face);

  /// The face drawn for this expression.
  final MoodFace face;

  /// The expression that goes with what an AI suggestion is saying: its
  /// `mood` word and how playful it is. An unknown word reads as [curious],
  /// the look of "here is a thought".
  static FlameyExpression forInsight({
    required String mood,
    String tone = 'normal',
  }) {
    final said = switch (mood) {
      'happy' => FlameyExpression.happy,
      'excited' => FlameyExpression.excited,
      'proud' => FlameyExpression.proud,
      'celebrating' => FlameyExpression.celebrating,
      'curious' => FlameyExpression.curious,
      'thinking' => FlameyExpression.thinking,
      'surprised' => FlameyExpression.surprised,
      'shocked' => FlameyExpression.shocked,
      'playful' => FlameyExpression.playful,
      'teasing' => FlameyExpression.teasing,
      'roasting' => FlameyExpression.roasting,
      'worried' => FlameyExpression.worried,
      'sad' => FlameyExpression.sad,
      'sleepy' => FlameyExpression.sleepy,
      _ => null,
    };
    if (said != null) return said;
    return switch (tone) {
      'roast' => FlameyExpression.roasting,
      'playful' => FlameyExpression.playful,
      _ => FlameyExpression.curious,
    };
  }
}

/// How Flamey moves when an expression arrives. One short, one-shot motion;
/// the widget plays it and comes to rest.
enum FlameyMotion { none, bounce, squash, nod, wiggle, shake }

/// Things that happen in the app that Flamey reacts to.
enum FlameyEvent {
  /// A page or tab was opened.
  pageOpened,

  /// The app was opened again after being away for a while.
  returned,

  /// Something the user set out to do was done.
  taskCompleted,

  /// An expense or income was saved. Pass the face that fits it.
  transaction,

  /// Money was saved: income arrived, or spending came down.
  savedMoney,

  /// The budget was passed, or spending jumped.
  overspent,

  /// A streak or savings milestone was reached.
  goalReached,

  /// Transactions were imported from a statement.
  imported,

  /// The AI is working on a suggestion. Stays until the next AI event.
  thinking,

  /// An AI suggestion, or a file's contents, has arrived to be looked at.
  suggestion,

  /// Something is loading. Stays until [success] or [error].
  loading,
  success,
  error,
}

/// Who wins when two things want Flamey's face at once.
enum _Priority { ambient, touch, important }

/// Timings for Flamey's behaviour, gathered here so they can be tuned (or
/// shortened in tests) without touching the logic.
class FlameyTimings {
  const FlameyTimings({
    this.idleMin = const Duration(seconds: 7),
    this.idleMax = const Duration(seconds: 13),
    this.idleGlance = const Duration(milliseconds: 1600),
    this.boredAfter = const Duration(seconds: 75),
    this.tapThrottle = const Duration(milliseconds: 220),
    this.tapStreakWindow = const Duration(milliseconds: 1800),
    this.touchReaction = const Duration(milliseconds: 1700),
    this.messageHold = const Duration(milliseconds: 2800),
    this.shortReaction = const Duration(milliseconds: 1500),
    this.reaction = const Duration(milliseconds: 2600),
    this.longReaction = const Duration(seconds: 4),
    this.stickyLimit = const Duration(seconds: 40),
  });

  /// An idle glance starts between [idleMin] and [idleMax] after the last.
  final Duration idleMin;
  final Duration idleMax;

  /// How long an idle glance lasts before the face goes back to rest.
  final Duration idleGlance;

  /// With no touch for this long, idle glances may show boredom.
  final Duration boredAfter;

  /// Taps closer together than this are ignored.
  final Duration tapThrottle;

  /// Taps within this window of each other count as one run of taps.
  final Duration tapStreakWindow;

  final Duration touchReaction;
  final Duration messageHold;
  final Duration shortReaction;
  final Duration reaction;
  final Duration longReaction;

  /// A loading or thinking state is dropped after this long even if nothing
  /// ever says it finished, so a lost reply cannot leave Flamey stuck.
  final Duration stickyLimit;
}

class _Reaction {
  const _Reaction({
    required this.face,
    required this.priority,
    this.motion = FlameyMotion.none,
    this.message,
    this.gaze = 0,
  });

  final MoodFace face;
  final _Priority priority;
  final FlameyMotion motion;
  final String? message;
  final double gaze;
}

/// Flamey's state machine.
///
/// What is shown is decided in one place, in this order:
///
///   1. a **reaction** - a timed response to a touch or an app event;
///   2. a **sticky** state - loading or thinking, until told it is over;
///   3. an **idle glance** - a brief, occasional change while nothing happens;
///   4. the **resting** face, given by the user's standing mood.
///
/// A reaction is replaced only by one of the same or higher priority (app
/// events < touch < success and error), so a tap is never talked over by a
/// page change, and an error is never hidden by a tap.
///
/// There is exactly one timer, re-armed for whatever comes next, and it only
/// runs while a Flamey is on screen and the app is in the foreground. Nothing
/// here touches the network: every expression comes from signals the app
/// already has.
class FlameyController extends ChangeNotifier {
  FlameyController({
    this.timings = const FlameyTimings(),
    math.Random? random,
    DateTime Function()? clock,
  }) : _random = random ?? math.Random(),
       _clock = clock ?? DateTime.now;

  final FlameyTimings timings;
  final math.Random _random;
  final DateTime Function() _clock;

  /// The controller above [context], or null where there is none (a preview,
  /// a test, a screen shown before sign-in).
  static FlameyController? maybeOf(BuildContext context) {
    try {
      return Provider.of<FlameyController>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }

  Timer? _timer;
  _Reaction? _reaction;
  DateTime? _reactionUntil;
  _Reaction? _sticky;
  DateTime? _stickySince;
  _Reaction? _glance;

  int _views = 0;
  bool _foreground = true;
  bool _disposed = false;

  DateTime? _lastTap;
  DateTime? _lastTouch;
  int _tapStreak = 0;
  int _tapCount = 0;
  int _serial = 0;

  // --- what is shown -------------------------------------------------------

  _Reaction? get _showing => _reaction ?? _sticky ?? _glance;

  /// The face to draw instead of the resting one, or null to draw the
  /// resting face.
  MoodFace? get face => _showing?.face;

  /// Where the eyes look: -1 left, 0 ahead, 1 right.
  double get gaze => _showing?.gaze ?? 0;

  /// The motion that goes with the current change. Play it once whenever
  /// [serial] changes.
  FlameyMotion get motion => _showing?.motion ?? FlameyMotion.none;

  /// A short line Flamey is saying, or null.
  String? get message => _reaction?.message;

  /// Goes up each time what is shown changes, so a view knows to replay the
  /// motion even when the same face is shown twice in a row.
  int get serial => _serial;

  bool get isReacting => _reaction != null;
  bool get isBusy => _sticky != null;

  @visibleForTesting
  bool get hasTimer => _timer?.isActive ?? false;

  // --- lifetime ------------------------------------------------------------

  /// A Flamey has come on screen. Idle glances only run while one is.
  void attach() {
    _views++;
    // Boredom is counted from when Flamey came on screen, not from never.
    _lastTouch ??= _clock();
    if (_views == 1) _arm();
  }

  /// A Flamey has left the screen.
  void detach() {
    if (_views > 0) _views--;
    if (_views == 0) {
      _glance = null;
      _arm();
    }
  }

  /// Call with false when the app goes to the background and true when it
  /// returns, so no timer runs while nobody can see Flamey.
  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (!value) _glance = null;
    _arm();
  }

  bool get _active => _views > 0 && _foreground && !_disposed;

  // --- app events ----------------------------------------------------------

  /// Reacts to something that happened in the app.
  ///
  /// [face] overrides the event's usual face (a saved transaction brings the
  /// face that suits its size), [hold] how long it stays, and [message] gives
  /// Flamey a line to say with it.
  void send(
    FlameyEvent event, {
    MoodFace? face,
    FlameyExpression? expression,
    Duration? hold,
    String? message,
  }) {
    if (_disposed) return;
    final wanted = face ?? expression?.face;
    switch (event) {
      case FlameyEvent.thinking:
      case FlameyEvent.loading:
        _sticky = _Reaction(
          face:
              wanted ??
              (event == FlameyEvent.loading
                  ? FlameyExpression.loading.face
                  : FlameyExpression.thinking.face),
          priority: _Priority.ambient,
        );
        _stickySince = _clock();
        _changed();
        return;
      case FlameyEvent.success:
        _sticky = null;
        _react(
          _Reaction(
            face: wanted ?? FlameyExpression.success.face,
            priority: _Priority.important,
            motion: FlameyMotion.bounce,
            message: message,
          ),
          hold ?? timings.reaction,
        );
        return;
      case FlameyEvent.error:
        _sticky = null;
        _react(
          _Reaction(
            face: wanted ?? FlameyExpression.error.face,
            priority: _Priority.important,
            motion: FlameyMotion.shake,
            message: message,
          ),
          hold ?? timings.reaction,
        );
        return;
      case FlameyEvent.suggestion:
        // Whatever was being waited for has arrived.
        _sticky = null;
        _ambient(
          wanted ?? FlameyExpression.curious.face,
          FlameyMotion.nod,
          hold ?? timings.reaction,
          message,
          always: true,
        );
        return;
      case FlameyEvent.pageOpened:
        _ambient(
          wanted ?? FlameyExpression.curious.face,
          FlameyMotion.nod,
          hold ?? timings.shortReaction,
          message,
        );
        return;
      case FlameyEvent.returned:
        _ambient(
          wanted ?? FlameyExpression.excited.face,
          FlameyMotion.bounce,
          hold ?? timings.reaction,
          message,
        );
        return;
      case FlameyEvent.taskCompleted:
        _ambient(
          wanted ?? FlameyExpression.happy.face,
          FlameyMotion.bounce,
          hold ?? timings.reaction,
          message,
        );
        return;
      case FlameyEvent.transaction:
        _ambient(
          wanted ?? FlameyExpression.playful.face,
          FlameyMotion.squash,
          hold ?? timings.longReaction,
          message,
        );
        return;
      case FlameyEvent.savedMoney:
        _ambient(
          wanted ?? FlameyExpression.moneySaving.face,
          FlameyMotion.bounce,
          hold ?? timings.longReaction,
          message,
        );
        return;
      case FlameyEvent.overspent:
        _ambient(
          wanted ?? FlameyExpression.overspending.face,
          FlameyMotion.shake,
          hold ?? timings.longReaction,
          message,
        );
        return;
      case FlameyEvent.goalReached:
        _ambient(
          wanted ?? FlameyExpression.goalReached.face,
          FlameyMotion.bounce,
          hold ?? timings.longReaction,
          message,
        );
        return;
      case FlameyEvent.imported:
        _sticky = null;
        _ambient(
          wanted ?? FlameyExpression.celebrating.face,
          FlameyMotion.bounce,
          hold ?? timings.longReaction,
          message,
          always: true,
        );
        return;
    }
  }

  /// Ends a loading or thinking state without a success or an error, e.g.
  /// when the thing being waited for was cancelled.
  void settle() {
    if (_sticky == null) return;
    _sticky = null;
    _changed();
  }

  void _ambient(
    MoodFace face,
    FlameyMotion motion,
    Duration hold,
    String? message, {
    bool always = false,
  }) {
    _react(
      _Reaction(
        face: face,
        priority: _Priority.ambient,
        motion: motion,
        message: message,
      ),
      hold,
      // A passing event does not interrupt what Flamey is busy with; the
      // result of that work does.
      overSticky: always,
    );
  }

  void _react(_Reaction next, Duration hold, {bool overSticky = true}) {
    final current = _reaction;
    if (current != null && next.priority.index < current.priority.index) {
      return;
    }
    if (!overSticky && _sticky != null) return;
    _reaction = next;
    _reactionUntil = _clock().add(hold);
    _glance = null;
    _serial++;
    _timer?.cancel();
    _timer = Timer(hold, _endReaction);
    notifyListeners();
  }

  // --- touch ---------------------------------------------------------------

  static const List<(MoodFace, FlameyMotion)> _tapFaces =
      <(MoodFace, FlameyMotion)>[
        (MoodFace.happy, FlameyMotion.bounce),
        (MoodFace.wink, FlameyMotion.squash),
        (MoodFace.surprised, FlameyMotion.squash),
        (MoodFace.excited, FlameyMotion.bounce),
        (MoodFace.curious, FlameyMotion.wiggle),
        (MoodFace.yum, FlameyMotion.squash),
      ];

  static const List<String> _tapLines = <String>[
    'Hehe, that tickles!',
    'Boop!',
    'Yes? I am listening 👀',
    'Careful, I am warm 🔥',
    'Poke me again, I dare you.',
    'Hi! Logged anything today?',
    'I was not sleeping. Promise.',
  ];

  static const List<String> _tooManyTaps = <String>[
    'Okay okay, I am dizzy now!',
    'Whoa, slow down! 😵',
    'I am a flame, not a drum!',
  ];

  int _lastLine = -1;

  String _line(List<String> lines) {
    var index = _random.nextInt(lines.length);
    if (lines.length > 1 && index == _lastLine) {
      index = (index + 1) % lines.length;
    }
    _lastLine = index;
    return lines[index];
  }

  /// The user tapped Flamey. Returns false when the tap came too soon after
  /// the last one and was ignored.
  bool tap() {
    if (_disposed) return false;
    final now = _clock();
    final last = _lastTap;
    if (last != null && now.difference(last) < timings.tapThrottle) {
      return false;
    }
    _tapStreak = last != null && now.difference(last) <= timings.tapStreakWindow
        ? _tapStreak + 1
        : 1;
    _lastTap = now;
    _lastTouch = now;
    _tapCount++;

    // A long run of taps gets its own answer; otherwise each tap moves on to
    // the next face, and now and then Flamey says something.
    if (_tapStreak >= 6) {
      _tapStreak = 0;
      _react(
        _Reaction(
          face: MoodFace.dizzy,
          priority: _Priority.touch,
          motion: FlameyMotion.shake,
          message: _line(_tooManyTaps),
        ),
        timings.messageHold,
      );
      return true;
    }
    final (face, motion) = _tapFaces[(_tapCount - 1) % _tapFaces.length];
    final speak = _tapCount % 3 == 1;
    _react(
      _Reaction(
        face: face,
        priority: _Priority.touch,
        motion: motion,
        message: speak ? _line(_tapLines) : null,
      ),
      speak ? timings.messageHold : timings.touchReaction,
    );
    return true;
  }

  /// The user is pressing and holding Flamey.
  void holdStart() {
    if (_disposed) return;
    _lastTouch = _clock();
    _react(
      const _Reaction(
        face: MoodFace.curious,
        priority: _Priority.touch,
        motion: FlameyMotion.squash,
      ),
      // Stays for as long as the finger is down; this only stops a missed
      // release from holding the face forever.
      timings.stickyLimit,
    );
  }

  /// The finger was lifted after [holdStart].
  void holdEnd() {
    if (_disposed) return;
    _lastTouch = _clock();
    // Let go: this ends the hold whatever else is queued behind it.
    _reaction = null;
    _react(
      const _Reaction(
        face: MoodFace.happy,
        priority: _Priority.touch,
        motion: FlameyMotion.bounce,
      ),
      timings.touchReaction,
    );
  }

  /// A swipe across or beside Flamey. [direction] is negative for left and
  /// positive for right; the eyes follow it.
  void swipe(double direction) {
    if (_disposed || direction == 0) return;
    final now = _clock();
    final last = _lastTouch;
    if (_reaction?.priority == _Priority.touch &&
        last != null &&
        now.difference(last) < timings.tapThrottle) {
      return;
    }
    _lastTouch = now;
    _react(
      _Reaction(
        face: MoodFace.surprised,
        priority: _Priority.touch,
        motion: FlameyMotion.wiggle,
        gaze: direction < 0 ? -1 : 1,
      ),
      timings.touchReaction,
    );
  }

  // --- the one timer -------------------------------------------------------

  void _changed() {
    _serial++;
    _arm();
    notifyListeners();
  }

  void _endReaction() {
    if (_disposed) return;
    _reaction = null;
    _reactionUntil = null;
    final since = _stickySince;
    if (_sticky != null &&
        since != null &&
        _clock().difference(since) >= timings.stickyLimit) {
      _sticky = null;
    }
    _changed();
  }

  void _endGlance() {
    if (_disposed) return;
    _glance = null;
    _changed();
  }

  /// Sets the single timer for whatever should happen next, or none.
  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (_disposed) return;
    if (_reaction != null) {
      // Something changed underneath a reaction: it keeps the time it had
      // left.
      final left = _reactionUntil?.difference(_clock()) ?? Duration.zero;
      _timer = Timer(left.isNegative ? Duration.zero : left, _endReaction);
      return;
    }
    if (_sticky != null) {
      _timer = Timer(timings.stickyLimit, () {
        if (_disposed) return;
        _sticky = null;
        _changed();
      });
      return;
    }
    if (!_active) return;
    if (_glance != null) {
      _timer = Timer(timings.idleGlance, _endGlance);
      return;
    }
    final span = timings.idleMax - timings.idleMin;
    final wait =
        timings.idleMin +
        Duration(
          milliseconds: span.inMilliseconds <= 0
              ? 0
              : _random.nextInt(span.inMilliseconds + 1),
        );
    _timer = Timer(wait, _startGlance);
  }

  void _startGlance() {
    if (_disposed || !_active || _reaction != null || _sticky != null) return;
    final now = _clock();
    final touched = _lastTouch;
    final untouched = touched == null
        ? timings.boredAfter
        : now.difference(touched);
    final night = now.hour >= 23 || now.hour < 5;

    final options = <_Reaction>[
      const _Reaction(
        face: MoodFace.curious,
        priority: _Priority.ambient,
        gaze: -1,
      ),
      const _Reaction(
        face: MoodFace.curious,
        priority: _Priority.ambient,
        gaze: 1,
      ),
      const _Reaction(
        face: MoodFace.calm,
        priority: _Priority.ambient,
        gaze: -1,
      ),
      const _Reaction(
        face: MoodFace.calm,
        priority: _Priority.ambient,
        gaze: 1,
      ),
      const _Reaction(
        face: MoodFace.happy,
        priority: _Priority.ambient,
        motion: FlameyMotion.nod,
      ),
      if (untouched >= timings.boredAfter)
        const _Reaction(face: MoodFace.bored, priority: _Priority.ambient),
      if (night)
        const _Reaction(face: MoodFace.sleepy, priority: _Priority.ambient),
    ];
    _glance = options[_random.nextInt(options.length)];
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
