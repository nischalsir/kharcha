import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: context.glass.background, child: child);
  }
}
