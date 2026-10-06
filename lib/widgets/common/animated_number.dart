import 'package:flutter/material.dart';

import '../../core/theme/motion.dart';
import '../../core/utils/currency_formatter.dart';

/// A figure that rolls to its new value when the value changes.
///
/// It shows the value it is given straight away. It used to count up from
/// zero every time a page opened, which made a balance that had not changed
/// look as if it had, and made the page wait to be read. Only a real change
/// moves it now, and with reduced motion not even that.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    this.formatter,
    this.style,
    this.textAlign,
    this.duration = const Duration(milliseconds: 380),
  });

  final double value;
  final String Function(double value)? formatter;
  final TextStyle? style;
  final TextAlign? textAlign;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final resolved = (style ?? DefaultTextStyle.of(context).style).copyWith(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    return TweenAnimationBuilder<double>(
      // Begins where it ends: nothing to play until the value changes, and
      // then it runs from the figure on screen to the new one.
      tween: Tween<double>(begin: value, end: value),
      duration: AppMotion.of(context, duration),
      curve: AppMotion.standard,
      builder: (context, current, _) {
        final text = formatter != null
            ? formatter!(current)
            : CurrencyFormatter.format(current);
        return Text(
          text,
          style: resolved,
          textAlign: textAlign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
