import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_failure.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/biometric_service.dart';
import '../../models/financial_summary.dart';
import '../../services/app_images.dart';
import 'flame_mascot.dart';
import 'pressable_scale.dart';

/// Presentation for the UI-agnostic [BiometricKind] reported by the service.
extension BiometricUi on BiometricKind {
  String get label => switch (this) {
    BiometricKind.face => 'Face unlock',
    BiometricKind.fingerprint => 'Fingerprint',
    BiometricKind.none => 'Biometrics',
  };

  IconData get icon => switch (this) {
    BiometricKind.face => Icons.face_retouching_natural_rounded,
    BiometricKind.fingerprint ||
    BiometricKind.none => Icons.fingerprint_rounded,
  };
}

/// Decides which account a successful fingerprint/face check is for.
///
/// The fingerprint belongs to the phone, not to an account, so it cannot tell
/// two people's accounts apart. With one account there is nothing to choose
/// and it is returned directly; with several the user has to pick, and
/// dismissing the sheet returns null so nobody is signed in by accident.
///
/// [avatarFor] supplies each account's saved profile picture. It is asked per
/// account, so one account's picture can never be drawn for another; where it
/// returns null, or the picture fails to load, the account's initial shows.
Future<BiometricAccount?> chooseBiometricAccount(
  BuildContext context,
  List<BiometricAccount> accounts, {
  ImageProvider? Function(BiometricAccount account)? avatarFor,
}) {
  if (accounts.isEmpty) return Future<BiometricAccount?>.value();
  if (accounts.length == 1) {
    return Future<BiometricAccount?>.value(accounts.single);
  }
  return showModalBottomSheet<BiometricAccount>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final glass = sheetContext.glass;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text(
                  'Choose an account',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  'More than one account uses this device to sign in. '
                  'Which one is yours?',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: glass.textSecondary,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final account in accounts)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                        ),
                        leading: _AccountAvatar(
                          // Keyed by account so a picture is never carried
                          // over to a different row.
                          key: ValueKey<String>(account.email),
                          initial: account.email[0].toUpperCase(),
                          image: avatarFor?.call(account),
                        ),
                        title: Text(
                          account.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: glass.textTertiary,
                        ),
                        onTap: () => Navigator.of(sheetContext).pop(account),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

/// An account's picture in a circle, cropped to fill it, with the account's
/// initial underneath for when there is no picture or it cannot be drawn.
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({super.key, required this.initial, this.image});

  final String initial;
  final ImageProvider? image;

  static const double _size = 40;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final letter = ColoredBox(
      color: theme.colorScheme.primary.withValues(alpha: 0.14),
      child: Center(
        child: Text(
          initial,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    final picture = image;
    return ClipOval(
      child: SizedBox(
        width: _size,
        height: _size,
        child: picture == null
            ? letter
            : Image(
                image: picture,
                width: _size,
                height: _size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                // Until the picture is decoded, and if it never is.
                frameBuilder: (_, child, frame, sync) =>
                    sync || frame != null ? child : letter,
                errorBuilder: (_, _, _) => letter,
              ),
      ),
    );
  }
}

/// Shared building blocks for the sign-in / sign-up screens so both pages
/// follow the same glass visual language as the rest of the app.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.maxWidth = 460});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.glass.background,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: SizedBox(
                    width: math.min(constraints.maxWidth, maxWidth),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gradient app mark + headline used at the top of the auth pages.
class AuthBrand extends StatelessWidget {
  const AuthBrand({
    super.key,
    required this.title,
    required this.subtitle,
    this.leading,
  });

  final String title;
  final String subtitle;
  final Widget? leading;

  /// How wide the logo is drawn.
  static const double logoSize = 76;

  /// Flamey, the app's logo, served by Cloudinary at the size it is shown.
  /// Replacing the image there under the same id changes the logo on the
  /// sign-in and sign-up screens without an app update.
  static String logoUrl(int pixelSize) =>
      'https://res.cloudinary.com/dh3rzo7bt/image/upload/'
      'c_fill,w_$pixelSize,h_$pixelSize,f_auto,q_auto/kharcha/brand/flamey-logo';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final glass = context.glass;

    const double size = logoSize;
    // Offline, or before the picture arrives: Flamey drawn by the app itself
    // on the brand's own tile, so the mark is never an empty box.
    final drawn = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[scheme.primary, scheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.all(10),
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: FlameMascot(face: MoodFace.happy, energy: 0.85, size: 56),
        ),
      ),
    );
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.32),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image(
        image: AppImages.provider(AuthBrand.logoUrl(pixels)),
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: 'Kharcha',
        frameBuilder: (_, child, frame, sync) =>
            sync || frame != null ? child : drawn,
        errorBuilder: (_, _, _) => drawn,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (leading != null) ...<Widget>[leading!, const SizedBox(height: 8)],
        Align(alignment: Alignment.centerLeft, child: mark),
        const SizedBox(height: 22),
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: glass.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// The kinds of notice the sign-in screens can show.
enum AuthNoticeKind { error, warning, success }

/// Shows a notice that slides up from the bottom of the screen and leaves on
/// its own. Showing another replaces it, so notices never stack.
void showAuthNotice(
  BuildContext context,
  String message, {
  AuthNoticeKind kind = AuthNoticeKind.error,
  IconData? icon,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final glass = context.glass;
  final accent = switch (kind) {
    AuthNoticeKind.error => glass.danger,
    AuthNoticeKind.warning => glass.warning,
    AuthNoticeKind.success => glass.success,
  };
  final symbol =
      icon ??
      switch (kind) {
        AuthNoticeKind.error => Icons.error_outline_rounded,
        AuthNoticeKind.warning => Icons.warning_amber_rounded,
        AuthNoticeKind.success => Icons.check_circle_outline_rounded,
      };
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        // Errors stay longer: they are the ones that have to be read.
        duration: Duration(seconds: kind == AuthNoticeKind.success ? 3 : 5),
        content: Row(
          children: <Widget>[
            Icon(symbol, color: accent, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

/// Turns whatever sign-in failure the [AuthProvider] reports into a notice
/// from the bottom of the screen.
///
/// Takes no space in the layout. It used to be a card above the form, which
/// pushed the whole form down whenever something went wrong.
class AuthFailureNotice extends StatefulWidget {
  const AuthFailureNotice({super.key});

  @override
  State<AuthFailureNotice> createState() => _AuthFailureNoticeState();
}

class _AuthFailureNoticeState extends State<AuthFailureNotice> {
  AuthProvider? _auth;

  /// The failure already shown, so one failure is announced once however
  /// many times the provider notifies while it is set.
  AppFailure? _shown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (identical(auth, _auth)) return;
    _auth?.removeListener(_onAuthChanged);
    _auth = auth..addListener(_onAuthChanged);
    _onAuthChanged();
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    final failure = _auth?.failure;
    if (failure == null) {
      _shown = null;
      return;
    }
    if (identical(failure, _shown)) return;
    _shown = failure;
    // After the frame: a notice cannot be shown while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showAuthNotice(
        context,
        failure.message,
        kind: failure.isOffline ? AuthNoticeKind.warning : AuthNoticeKind.error,
        icon: failure.isOffline ? Icons.wifi_off_rounded : null,
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Glass secondary button (biometric sign-in, continue as guest, …).
class AuthGhostButton extends StatelessWidget {
  const AuthGhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tint,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final color = tint ?? theme.colorScheme.primary;
    final enabled = onPressed != null;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: PressableScale(
        onTap: onPressed,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: glass.fill,
            borderRadius: BorderRadius.circular(27),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Label + optional subtitle with a trailing switch, used for "remember me"
/// on the login page and for the biometric preference in settings.
class AuthSwitchRow extends StatelessWidget {
  const AuthSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.enabled = true,
  });

  final String label;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final scheme = theme.colorScheme;
    final color = enabled ? scheme.onSurface : scheme.onSurfaceVariant;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: PressableScale(
        onTap: enabled ? () => onChanged?.call(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(
                  icon,
                  size: 20,
                  color: value ? scheme.primary : glass.textSecondary,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(color: color),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: glass.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: value,
                onChanged: enabled ? onChanged : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
