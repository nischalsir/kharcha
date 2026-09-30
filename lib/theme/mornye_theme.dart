import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Flutter counterpart of Mornye's iPhone visual system.
///
/// Keeps the palette independent of wallpaper colors while using iOS system
/// semantics for surfaces and type. Works with [liquid_glass_easy] for the
/// refractive glass layer on supported platforms.
@immutable
class MornyeTheme extends ThemeExtension<MornyeTheme> {
  const MornyeTheme({
    this.chromeSurface,
    this.accent = MornyeAccent.red,
    this.useSystemFont = false,
  });

  /// Optional artwork-driven surface color for the chrome (tabs, sheets).
  final Color? chromeSurface;

  /// The accent color family.
  final MornyeAccent accent;

  /// Use the platform's default font (SF Pro on Apple, Roboto on Android)
  /// instead of Inter.
  final bool useSystemFont;

  /// A single translucent fill for controls inside an existing glass surface.
  static Color controlFill(BuildContext context, {bool enabled = true}) {
    final theme = Theme.of(context);
    return theme.colorScheme.onSurface.withValues(
      alpha: !enabled
          ? 0.04
          : theme.brightness == Brightness.dark
          ? 0.10
          : 0.07,
    );
  }

  /// Separators blend with their group, keeping definition on pages and sheets.
  static Color metadataDividerColor(BuildContext context) {
    final theme = Theme.of(context);
    return theme.colorScheme.onSurface.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.14 : 0.17,
    );
  }

  /// Opacity of the main chrome surface (tabs, app bars).
  static double chromeOpacity(BuildContext context) =>
      Theme.of(context).extension<MornyeTheme>()?.chromeSurface != null
      ? 0.42
      : 0.70;

  /// Opacity of the navigation bar surface.
  static double navigationOpacity(BuildContext context) =>
      Theme.of(context).extension<MornyeTheme>()?.chromeSurface != null
      ? 0.28
      : 0.54;

  static const lightAccent = Color.fromRGBO(204, 46, 51, 1);
  static const darkAccent = Color.fromRGBO(224, 61, 60, 1);

  static Color accentColor(MornyeAccent accent, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final color = switch (accent) {
      MornyeAccent.red => const CupertinoDynamicColor.withBrightness(
        color: lightAccent,
        darkColor: darkAccent,
      ),
      MornyeAccent.orange => CupertinoColors.systemOrange,
      MornyeAccent.green => CupertinoColors.systemGreen,
      MornyeAccent.teal => CupertinoColors.systemTeal,
      MornyeAccent.blue => CupertinoColors.systemBlue,
      MornyeAccent.purple => CupertinoColors.systemPurple,
      MornyeAccent.pink => CupertinoColors.systemPink,
    };
    if (!dark && accent == MornyeAccent.green) return const Color(0xff24863d);
    return dark ? color.darkColor : color.highContrastColor;
  }

  /// Token overrides specific to the Mornye visual language.
  static final tokens = AppTokens.standard.copyWith(
    radiusBadge: 5,
    radiusThumb: 6,
    radiusCover: 10,
    radiusControl: 12,
    radiusCard: 12,
    radiusSheet: 32,
    coverMini: 38,
    headerExpandedTitleSize: 34,
    headerCollapsedTitleSize: 17,
    motionFast: const Duration(milliseconds: 180),
    motionMedium: const Duration(milliseconds: 220),
    motionSlow: const Duration(milliseconds: 380),
    rowPaddingH: 16,
    rowPaddingV: 10,
    rowPaddingVCompact: 8,
    rowIconGap: 12,
    rowIconDividerIndent: 52,
    rowChevronSize: 18,
    rowMinHeight: 28,
    trackRowPaddingV: 12,
    headerSubtitleSize: 20,
    lyricsLineHeight: 1.3,
    lyricsLinePaddingV: 16,
    playerControlGap: 12,
    dialogInsetH: 24,
  );

  // Theme construction includes seeded color generation and typography. Reuse
  // identical themes across routes; bound artwork-derived variants so browsing
  // many artists cannot grow the cache indefinitely. Platform is part of the
  // key because it controls fonts and route transitions.
  static final _themeCache =
      <(TargetPlatform, Brightness, Color?, MornyeAccent, bool), ThemeData>{};

  static ThemeData build(
    Brightness brightness, {
    Color? chromeSurface,
    MornyeAccent accent = MornyeAccent.red,
    bool useSystemFont = false,
  }) {
    final key = (
      defaultTargetPlatform,
      brightness,
      chromeSurface,
      accent,
      useSystemFont,
    );
    final cached = _themeCache.remove(key);
    if (cached != null) {
      _themeCache[key] = cached;
      return cached;
    }
    final theme = _build(
      brightness,
      chromeSurface: chromeSurface,
      selectedAccent: accent,
      useSystemFont: useSystemFont,
    );
    if (_themeCache.length >= 16) {
      _themeCache.remove(_themeCache.keys.first);
    }
    _themeCache[key] = theme;
    return theme;
  }

  /// Rebuild local surfaces without losing the user's Mornye preferences.
  static ThemeData fromContext(
    BuildContext context, {
    Brightness? brightness,
    Color? chromeSurface,
  }) {
    final theme = Theme.of(context);
    final preferences = theme.extension<MornyeTheme>();
    return build(
      brightness ?? theme.brightness,
      chromeSurface: chromeSurface,
      accent: preferences?.accent ?? MornyeAccent.red,
      useSystemFont: preferences?.useSystemFont ?? false,
    );
  }

  static ThemeData _build(
    Brightness brightness, {
    Color? chromeSurface,
    required MornyeAccent selectedAccent,
    required bool useSystemFont,
  }) {
    final dark = brightness == Brightness.dark;
    final accent = accentColor(selectedAccent, brightness);
    final foreground = dark ? Colors.white : Colors.black;
    final surface = dark ? Colors.black : Colors.white;
    final grouped = dark ? const Color(0xff1c1c1e) : const Color(0xfff2f2f7);
    final secondary = dark ? const Color(0xff98989f) : const Color(0xff6c6c70);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          onPrimary:
              selectedAccent == MornyeAccent.red ||
                  accent.computeLuminance() < 0.179
              ? Colors.white
              : Colors.black,
          primaryContainer: grouped,
          onPrimaryContainer: accent,
          secondary: accent,
          onSecondary: Colors.white,
          secondaryContainer: grouped,
          onSecondaryContainer: foreground,
          surface: surface,
          onSurface: foreground,
          surfaceContainerLowest: surface,
          surfaceContainerLow: grouped,
          surfaceContainer: grouped,
          surfaceContainerHigh: chromeSurface == null
              ? (dark ? const Color(0xff2c2c2e) : grouped)
              : Color.lerp(chromeSurface, Colors.black, 0.16),
          surfaceContainerHighest: dark
              ? const Color(0xff3a3a3c)
              : const Color(0xffe5e5ea),
          onSurfaceVariant: secondary,
          outline: secondary,
          outlineVariant: dark
              ? const Color(0xff38383a)
              : const Color(0xffc6c6c8),
          surfaceTint: Colors.transparent,
        );
    // Cupertino's font proxies resolve to SF on Apple and the platform fallback
    // elsewhere. Inter remains the default on other platforms unless opted out.
    final apple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final type = CupertinoThemeData(brightness: brightness).textTheme;
    final text = type.textStyle.copyWith(
      inherit: true,
      color: foreground,
      fontFamily: apple || useSystemFont ? type.textStyle.fontFamily : 'Inter',
    );
    final display = type.navLargeTitleTextStyle.copyWith(
      inherit: true,
      color: foreground,
      fontFamily: apple || useSystemFont
          ? type.navLargeTitleTextStyle.fontFamily
          : 'Inter',
    );
    // Supply complete styles: replacing a Material role with a bare TextStyle
    // loses its system family and retains Material tracking in other roles.
    final typography = TextTheme(
      displayLarge: display.copyWith(fontSize: 57),
      displayMedium: display.copyWith(fontSize: 45),
      displaySmall: display.copyWith(fontSize: 36),
      headlineLarge: display,
      headlineMedium: display.copyWith(fontSize: 28, letterSpacing: 0.36),
      headlineSmall: display.copyWith(fontSize: 22, letterSpacing: 0.35),
      titleLarge: display.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.38,
      ),
      titleMedium: text.copyWith(fontWeight: FontWeight.w500),
      titleSmall: text.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.23,
      ),
      bodyLarge: text,
      bodyMedium: text.copyWith(fontSize: 15, letterSpacing: -0.23),
      bodySmall: text.copyWith(
        fontSize: 13,
        letterSpacing: -0.08,
        color: secondary,
      ),
      labelLarge: text.copyWith(fontWeight: FontWeight.w600),
      labelMedium: text.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.08,
      ),
      labelSmall: text.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.24,
        color: secondary,
      ),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      fontFamily: text.fontFamily,
      splashFactory: NoSplash.splashFactory,
      extensions: <ThemeExtension<dynamic>>[
        MornyeTheme(
          chromeSurface: chromeSurface,
          accent: selectedAccent,
          useSystemFont: useSystemFont,
        ),
        tokens,
      ],
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return base.copyWith(
      textTheme: typography,
      primaryTextTheme: typography.apply(
        bodyColor: scheme.onPrimary,
        displayColor: scheme.onPrimary,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: accent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: text.copyWith(fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        color: grouped,
        elevation: 0,
        shape: controlShape,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 0.5,
        space: 0.5,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: accent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        shape: controlShape,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: controlShape,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: controlShape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: controlShape),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: grouped,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: grouped,
        surfaceTintColor: Colors.transparent,
        constraints: const BoxConstraints(maxWidth: 640),
        shape: tokens.sheetShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: grouped,
        shape: controlShape,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHigh,
        contentTextStyle: text.copyWith(fontSize: 15, color: foreground),
        actionTextColor: accent,
        disabledActionTextColor: secondary,
        closeIconColor: foreground,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  @override
  MornyeTheme copyWith({
    Color? chromeSurface,
    MornyeAccent? accent,
    bool? useSystemFont,
  }) => MornyeTheme(
    chromeSurface: chromeSurface ?? this.chromeSurface,
    accent: accent ?? this.accent,
    useSystemFont: useSystemFont ?? this.useSystemFont,
  );

  @override
  MornyeTheme lerp(covariant MornyeTheme? other, double t) => MornyeTheme(
    chromeSurface: Color.lerp(chromeSurface, other?.chromeSurface, t),
    accent: t < 0.5 ? accent : other?.accent ?? accent,
    useSystemFont: t < 0.5
        ? useSystemFont
        : other?.useSystemFont ?? useSystemFont,
  );
}

extension MornyeThemeContext on BuildContext {
  bool get isMornye => Theme.of(this).extension<MornyeTheme>() != null;
}

/// Accent families available in Mornye. Matches iOS's system palette.
enum MornyeAccent { red, orange, green, teal, blue, purple, pink }
