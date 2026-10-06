import 'package:flutter/material.dart';

import '../../theme/mornye_theme.dart';

/// Backward-compatible [GlassTheme]-style accessor used by existing widgets.
extension GlassContext on BuildContext {
  GlassThemeCompat get glass => GlassThemeCompat(this);
}

/// Compatibility layer providing the old [GlassTheme] API on top of Mornye's
/// [ColorScheme] and [MornyeTheme] extensions. This lets existing widgets
/// keep using `context.glass.background`, `context.glass.surface`, etc.
class GlassThemeCompat {
  GlassThemeCompat(this._context);

  final BuildContext _context;

  ThemeData get _theme => Theme.of(_context);
  ColorScheme get _scheme => _theme.colorScheme;
  bool get _dark => _scheme.brightness == Brightness.dark;

  Color get background => _dark ? Colors.black : Colors.white;
  Color get surface =>
      _dark ? const Color(0xff1c1c1e) : const Color(0xfff2f2f7);
  // In light mode the page background is white and grouped surfaces are grey,
  // so "strong" cards step up to pure white to keep their definition instead
  // of blending into the surrounding grey.
  Color get surfaceStrong => _dark ? const Color(0xff2c2c2e) : Colors.white;
  Color get sheet => _dark ? const Color(0xff1c1c1e) : const Color(0xfff2f2f7);
  Color get fill => _scheme.onSurface.withValues(alpha: _dark ? 0.10 : 0.07);
  Color get border => _dark ? const Color(0xff38383a) : const Color(0xffc6c6c8);
  Color get separator =>
      _dark ? const Color(0xff38383a) : const Color(0xffc6c6c8);
  Color get shadow => Colors.transparent;
  Color get glow => Colors.transparent;
  Color get textSecondary =>
      _dark ? const Color(0xff98989f) : const Color(0xff6c6c70);
  Color get textTertiary => _dark
      ? const Color(0xff98989f).withValues(alpha: 0.5)
      : const Color(0xff6c6c70).withValues(alpha: 0.5);
  /// A hairline between rows that share a card.
  Color get hairline => _scheme.onSurface.withValues(alpha: _dark ? 0.14 : 0.10);
  // The bright system colours are made for a black page. As text on white or
  // on a light grey card they are too pale to read (the green is 2:1), so
  // light mode uses the darker of each pair, all above 4.5:1 on a card.
  Color get success =>
      _dark ? const Color(0xff30d158) : const Color(0xff1a7f37);
  Color get warning =>
      _dark ? const Color(0xffff9f0a) : const Color(0xffb25000);
  // On a dark card the standard red is 4:1, so the lighter of that pair.
  Color get danger => _dark ? const Color(0xffff6961) : const Color(0xffd70015);
  List<Color> get backgroundGradient => _dark
      ? const [Color(0xff000000), Color(0xff000000)]
      : const [Color(0xffffffff), Color(0xffffffff)];
}

class AppTheme {
  const AppTheme._();

  static ThemeData light({bool useSystemFont = false}) =>
      MornyeTheme.build(Brightness.light, useSystemFont: useSystemFont);

  static ThemeData dark({bool useSystemFont = false}) =>
      MornyeTheme.build(Brightness.dark, useSystemFont: useSystemFont);
}
