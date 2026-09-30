import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../theme/mornye_theme.dart';

/// Metrics helper to match the platform's native rendering for the glass lens.
class _NativeGlassMetrics extends StatelessWidget {
  const _NativeGlassMetrics({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        size: view.physicalSize / view.devicePixelRatio,
        devicePixelRatio: view.devicePixelRatio,
      ),
      child: child,
    );
  }
}

/// The bounded, translucent chrome used by Mornye's tab accessory, sheets,
/// dialogs and floating controls. Blur follows the app's device performance
/// gate and accessibility settings.
class MornyeGlass extends StatelessWidget {
  const MornyeGlass({
    super.key,
    required this.child,
    required this.blurEnabled,
    this.radius = 32,
    this.strongTint = false,
    this.tintOpacity,
    this.tintColor,
    this.backdropFilter,
  }) : _useLens = true,
       firstInGroup = true,
       lastInGroup = true,
       intensity = 1;

  /// Shares the navigation bar's tint, blur and visible outer rim.
  const MornyeGlass.navigation({
    super.key,
    required this.child,
    required this.blurEnabled,
    this.radius = 32,
    this.firstInGroup = true,
    this.lastInGroup = true,
    this.strongTint = false,
    this.tintOpacity,
    this.tintColor,
    this.backdropFilter,
    this.intensity = 1,
  }) : _useLens = false;

  final Widget child;
  final bool blurEnabled;
  final double radius;
  final bool _useLens;
  final bool firstInGroup;
  final bool lastInGroup;

  /// Keeps floating controls readable over arbitrary backgrounds.
  final bool strongTint;

  /// Uses a single tint instead of layered highlights for translucent surfaces.
  final double? tintOpacity;
  final Color? tintColor;
  final ImageFilter? backdropFilter;

  /// Scales rim, shadow and fill so the glass reads denser as the navigation
  /// compresses, without ever re-creating the (expensive) blur filter.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final useGlass =
        _useLens && blurEnabled && !MediaQuery.highContrastOf(context);
    return _MornyeGlassSurface(
      blurEnabled: blurEnabled,
      radius: radius,
      firstInGroup: firstInGroup,
      lastInGroup: lastInGroup,
      strongTint: strongTint,
      tintOpacity: tintOpacity,
      tintColor: tintColor,
      backdropFilter: backdropFilter,
      intensity: intensity,
      child: useGlass
          ? _NativeGlassMetrics(
              child: LiquidGlassLens(
                style: LiquidGlassStyle(
                  shape: LiquidGlassShape.continuousRoundedRectangle(
                    cornerRadius: radius,
                    borderWidth: dark && tintOpacity == null ? 0 : 0.6,
                    lightIntensity: dark && tintOpacity == null ? 0 : 0.18,
                  ),
                  appearance: LiquidGlassAppearance(
                    color: tintOpacity != null
                        ? Colors.transparent
                        : dark
                        ? scheme.surfaceContainerHigh.withValues(alpha: 0.28)
                        : Colors.white.withValues(
                            alpha: strongTint ? 0.20 : 0.55,
                          ),
                    blur: const LiquidGlassBlur(),
                  ),
                  refraction: const LiquidGlassRefraction(
                    distortion: 0.02,
                    distortionWidth: 8,
                    chromaticAberration: 0,
                  ),
                ),
                child: MediaQuery(data: MediaQuery.of(context), child: child),
              ),
            )
          : child,
    );
  }
}

/// Keep the capsule legible independently of the shader renderer. The liquid
/// lens adds refraction above this frosted base, never above bare page text.
class _MornyeGlassSurface extends StatelessWidget {
  static final _backdropBlur = ImageFilter.blur(sigmaX: 18, sigmaY: 18);

  const _MornyeGlassSurface({
    required this.child,
    required this.blurEnabled,
    this.radius = 32,
    this.firstInGroup = true,
    this.lastInGroup = true,
    this.strongTint = false,
    this.tintOpacity,
    this.tintColor,
    this.backdropFilter,
    this.intensity = 1,
  });

  final Widget child;
  final bool blurEnabled;
  final double radius;
  final bool firstInGroup;
  final bool lastInGroup;
  final bool strongTint;
  final double? tintOpacity;
  final Color? tintColor;
  final ImageFilter? backdropFilter;

  /// Scales rim, shadow and fill so the glass reads denser as the navigation
  /// compresses, without ever re-creating the (expensive) blur filter.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final useBlur = blurEnabled && !MediaQuery.highContrastOf(context);
    final dark = scheme.brightness == Brightness.dark;
    final shape = BorderRadius.vertical(
      top: firstInGroup ? Radius.circular(radius) : Radius.zero,
      bottom: lastInGroup ? Radius.circular(radius) : Radius.zero,
    );
    final rim = BorderSide(
      color: dark
          ? Colors.white.withValues(alpha: tintColor == null ? 0.16 : 0.28)
          : Colors.black.withValues(alpha: 0.17),
      width: 0.75,
    );
    final border = Border(
      top: firstInGroup ? rim : BorderSide.none,
      bottom: lastInGroup ? rim : BorderSide.none,
      left: rim,
      right: rim,
    );
    // A translucent white tint must not become solid white behind light
    // text when accessibility or the device profile disables blur.
    final tint = useBlur
        ? tintColor ?? scheme.surfaceContainerHigh
        : scheme.surfaceContainerHigh;
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: tint.withValues(
          alpha: useBlur
              ? (tintOpacity ?? (strongTint ? 0.80 : 0.60)) *
                    intensity.clamp(1.0, 1.55)
              : 1,
        ),
        gradient: useBlur && !dark && tintOpacity == null
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.35, 0.75, 1],
                colors: [
                  Colors.white.withValues(alpha: 0.90 * intensity),
                  Colors.white.withValues(
                    alpha: (strongTint ? 0.80 : 0.78) * intensity,
                  ),
                  scheme.surfaceContainerHigh.withValues(
                    alpha:
                        (strongTint ? 0.76 : 0.72) * intensity.clamp(1.0, 1.55),
                  ),
                  Colors.white.withValues(alpha: 0.85 * intensity),
                ],
              )
            : null,
        borderRadius: shape,
        border: dark ? border : null,
      ),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: firstInGroup && lastInGroup
            ? [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: (dark ? 0.2 : 0.06) * intensity,
                  ),
                  blurRadius: (dark ? 18 : 10) * intensity,
                  // Clear glass keeps its tint; the shadow belongs outside
                  // the panel, not underneath its translucent center.
                  blurStyle: tintColor == null
                      ? BlurStyle.normal
                      : BlurStyle.outer,
                  offset: Offset(0, (dark ? 4 : 2) * intensity),
                ),
              ]
            : null,
      ),
      child: DecoratedBox(
        // Paint the light outline above the lens so its pale tint cannot wash
        // the edge out on an all-white page. Dark chrome keeps its quiet rim.
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: shape,
          border: dark ? null : border,
        ),
        child: ClipRRect(
          borderRadius: shape,
          child: useBlur
              ? BackdropFilter(
                  filter: backdropFilter ?? _backdropBlur,
                  child: surface,
                )
              : surface,
        ),
      ),
    );
  }
}

/// A searchable category chip uses the same material as the navigation capsule.
class MornyeFilterChip extends StatelessWidget {
  const MornyeFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.blurEnabled = true,
    this.glass = true,
    this.tonal = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool blurEnabled;
  final bool glass;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: Material(
        color: !glass && !tonal
            ? Colors.transparent
            : selected
            ? scheme.primary.withValues(alpha: 0.12)
            : glass
            ? Colors.transparent
            : MornyeTheme.controlFill(context, enabled: onTap != null),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: selected ? scheme.primary : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!glass) {
      return ClipRRect(borderRadius: BorderRadius.circular(24), child: content);
    }
    return MornyeGlass.navigation(
      radius: 24,
      blurEnabled: blurEnabled,
      child: content,
    );
  }
}
