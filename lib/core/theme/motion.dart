import 'package:flutter/widgets.dart';

import '../../theme/mornye_theme.dart';

/// How the app moves.
///
/// Anything a finger drives uses a spring: it starts from wherever the thing
/// is, carries its speed, and can be turned around at any moment. Timed
/// curves are for changes nobody is holding on to (a number updating, a
/// placeholder giving way to content), and none of them overshoot.
class AppMotion {
  const AppMotion._();

  static Duration get fast => MornyeTheme.tokens.motionFast;
  static Duration get medium => MornyeTheme.tokens.motionMedium;
  static Duration get slow => MornyeTheme.tokens.motionSlow;

  static const Curve standard = Curves.easeOutCubic;

  /// A firmer arrival than [standard], still without overshoot: a bounce
  /// belongs to something that was thrown, not to something that appeared.
  static const Curve emphasized = Cubic(0.05, 0.7, 0.1, 1.0);

  /// Critically damped, settling in about a third of a second. The default
  /// for anything that follows a touch.
  static final SpringDescription spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 320,
    ratio: 1,
  );

  /// Going down under a finger: quick enough to be felt as the touch itself.
  static final SpringDescription press = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 1400,
    ratio: 1,
  );

  /// Coming back up once the finger has left.
  static final SpringDescription release = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 520,
    ratio: 1,
  );

  /// Whether the person has asked the system for less motion. Movement is
  /// then replaced by a plain change or a short fade; feedback itself stays.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or none at all when motion is reduced.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}
