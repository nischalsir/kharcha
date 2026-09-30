import 'package:flutter/material.dart';

import '../../core/utils/currency_formatter.dart';

class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    this.formatter,
    this.style,
    this.textAlign,
    this.duration = const Duration(milliseconds: 700),
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
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
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
