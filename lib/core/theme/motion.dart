import 'package:flutter/animation.dart';

import '../../theme/app_tokens.dart';

class AppMotion {
  const AppMotion._();

  static Duration get fast => AppTokens.standard.motionFast;
  static Duration get medium => AppTokens.standard.motionMedium;
  static Duration get slow => AppTokens.standard.motionSlow;

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutBack;
}
