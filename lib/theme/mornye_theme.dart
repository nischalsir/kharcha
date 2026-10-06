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

  /// Kept for callers that still pass it. Every platform now uses its own
  /// system font (SF Pro on Apple, Roboto on Android): the Inter this used to
  /// opt out of was named here but never bundled, so it was never drawn.
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
    radiusCard: 20,
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
    // Apple platforms keep SF and Apple's own tracking table. Everywhere else
    // the system font is used with tracking tuned for it: SF's display
    // sizes are spaced *wider* as they grow, which on Roboto reads as loose
    // headings, so large text is tightened and the smallest opened a little.
    final apple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final type = CupertinoThemeData(brightness: brightness).textTheme;
    final systemFamily = Typography.material2021(
      platform: defaultTargetPlatform,
    ).black.bodyMedium?.fontFamily;
    final text = type.textStyle.copyWith(
      inherit: true,
      color: foreground,
      fontFamily: apple ? type.textStyle.fontFamily : systemFamily,
      letterSpacing: apple ? null : -0.1,
    );
    final display = type.navLargeTitleTextStyle.copyWith(
      inherit: true,
      color: foreground,
      fontFamily: apple ? type.navLargeTitleTextStyle.fontFamily : systemFamily,
      letterSpacing: apple ? null : -0.6,
    );
    // Size-specific tracking: (Apple, everything else).
    double track(double sf, double system) => apple ? sf : system;
    // Supply complete styles: replacing a Material role with a bare TextStyle
    // loses its system family and retains Material tracking in other roles.
    final typography = TextTheme(
      displayLarge: display.copyWith(
        fontSize: 57,
        letterSpacing: apple ? null : -1.2,
      ),
      displayMedium: display.copyWith(
        fontSize: 45,
        letterSpacing: apple ? null : -0.9,
      ),
      displaySmall: display.copyWith(
        fontSize: 36,
        letterSpacing: apple ? null : -0.7,
      ),
      headlineLarge: display,
      headlineMedium: display.copyWith(
        fontSize: 28,
        letterSpacing: track(0.36, -0.45),
      ),
      headlineSmall: display.copyWith(
        fontSize: 22,
        letterSpacing: track(0.35, -0.3),
      ),
      titleLarge: display.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: track(0.38, -0.2),
      ),
      titleMedium: text.copyWith(fontWeight: FontWeight.w500),
      titleSmall: text.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: track(-0.23, 0),
      ),
      bodyLarge: text,
      bodyMedium: text.copyWith(fontSize: 15, letterSpacing: track(-0.23, 0)),
      bodySmall: text.copyWith(
        fontSize: 13,
        letterSpacing: track(-0.08, 0.05),
        color: secondary,
      ),
      labelLarge: text.copyWith(fontWeight: FontWeight.w600),
      labelMedium: text.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: track(-0.08, 0.05),
      ),
      labelSmall: text.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: track(-0.24, 0.1),
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
      borderRadius: BorderRadius.circular(tokens.radiusControl),
    );
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radiusCard),
    );
    // Every button is a capsule, the shape PrimaryButton already had, so a
    // dialog's buttons and a page's buttons are the same family.
    const buttonShape = StadiumBorder();
    // A pop-up floats over a dimmed page: its shadow separates it. Only on
    // black does it also need a faint rim, where a shadow cannot be seen.
    final popupShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(28),
      side: dark
          ? BorderSide(color: Colors.white.withValues(alpha: 0.12), width: 0.75)
          : BorderSide.none,
    );
    // A pop-up's own colour. White in light mode, so the grey text fields and
    // cards inside it keep an edge.
    final popupSurface = dark ? const Color(0xff2c2c2e) : Colors.white;
    final neutralFill = foreground.withValues(alpha: dark ? 0.10 : 0.07);
    final accentFill = accent.withValues(alpha: dark ? 0.24 : 0.14);
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
      cardTheme: CardThemeData(color: grouped, elevation: 0, shape: cardShape),
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
          shape: buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        ),
      ),
      // The third kind of button: words alone, a size down from a filled
      // button, so a link inside a card does not shout over the card.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: buttonShape,
          textStyle: text.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: track(-0.23, 0),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: buttonShape,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      // Choice chips are quiet pills: a neutral fill, and the accent as a
      // tint when chosen. No outline and no tick, which only repeated what
      // the colour already says.
      chipTheme: ChipThemeData(
        showCheckmark: false,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        // A solid neutral, not a tint: a chip is drawn on its own canvas, so
        // a tint came out the same grey whatever was behind it, and on a
        // dark sheet that grey was the sheet's.
        color: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accentFill
              : scheme.surfaceContainerHighest,
        ),
        labelStyle: text.copyWith(
          fontSize: 15,
          letterSpacing: track(-0.23, 0),
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? secondary
                : states.contains(WidgetState.selected)
                ? accent
                : foreground,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: grouped,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusControl),
          borderSide: BorderSide.none,
        ),
        // Which field has the keyboard is shown by the field, not only by
        // its cursor.
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusControl),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: grouped,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        dragHandleColor: foreground.withValues(alpha: dark ? 0.2 : 0.15),
        dragHandleSize: const Size(36, 5),
        constraints: const BoxConstraints(maxWidth: 640),
        shape: tokens.sheetShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: popupSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.5 : 0.2),
        elevation: 6,
        shape: popupShape,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: popupSurface,
        surfaceTintColor: Colors.transparent,
        shape: popupShape,
      ),
      // The floating button is the page's main action, so it is the same
      // filled capsule as every other main action.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        highlightElevation: 2,
        shape: buttonShape,
        extendedTextStyle: text.copyWith(fontWeight: FontWeight.w600),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: neutralFill,
        circularTrackColor: Colors.transparent,
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
