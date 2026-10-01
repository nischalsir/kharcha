import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/account_avatar_cache.dart';
import 'glass_background.dart';

/// The full-screen "Signing in as …" / "Signing out…" state.
///
/// Shown while an account is being entered or left, in place of whatever was
/// on screen, so no page built for one account is ever visible while the app
/// is moving to another.
class AccountTransitionView extends StatelessWidget {
  /// Signing in: names the account, with its own saved picture.
  const AccountTransitionView.signingIn({super.key, required this._email})
    : _signingOut = false;

  /// Signing out: deliberately anonymous. Nothing about any account is shown.
  const AccountTransitionView.signingOut({super.key})
    : _email = null,
      _signingOut = true;

  final String? _email;
  final bool _signingOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final email = _email;

    return GlassBackground(
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Semantics(
                liveRegion: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (!_signingOut && email != null) ...<Widget>[
                      Text(
                        context.t('Signing in as', 'यस खाताबाट साइन इन हुँदै'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: glass.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Keyed by email: a different account is a different
                      // widget, so one account's picture can never linger
                      // under another's address.
                      _TransitionAvatar(
                        key: ValueKey<String>(email),
                        email: email,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        email,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else
                      Text(
                        _signingOut
                            ? context.t('Signing out…', 'साइन आउट हुँदैछ…')
                            : context.t('Signing in…', 'साइन इन हुँदैछ…'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(height: 22),
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The picture saved for [email], or its initial when there is none.
class _TransitionAvatar extends StatefulWidget {
  const _TransitionAvatar({super.key, required this.email});

  final String email;

  @override
  State<_TransitionAvatar> createState() => _TransitionAvatarState();
}

class _TransitionAvatarState extends State<_TransitionAvatar> {
  Future<File?>? _file;

  @override
  void initState() {
    super.initState();
    try {
      _file = context.read<AccountAvatarCache>().fileFor(widget.email);
    } catch (_) {
      // No avatar store provided (a test, a preview): the initial is shown.
      _file = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const double size = 76;
    final email = widget.email.trim();
    final letter = ColoredBox(
      color: theme.colorScheme.primary.withValues(alpha: 0.16),
      child: Center(
        child: Text(
          email.isEmpty ? '?' : email[0].toUpperCase(),
          style: theme.textTheme.headlineMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: FutureBuilder<File?>(
          future: _file,
          builder: (context, snapshot) {
            final file = snapshot.data;
            if (file == null) return letter;
            return Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              frameBuilder: (_, child, frame, sync) =>
                  sync || frame != null ? child : letter,
              errorBuilder: (_, _, _) => letter,
            );
          },
        ),
      ),
    );
  }
}

/// Lays [AccountTransitionView] over the whole app while the [AuthProvider]
/// is signing in or out. It sits above the navigator, so it covers pushed
/// screens and dialogs too, and swallows taps so nothing can be pressed
/// twice.
class AccountTransitionOverlay extends StatelessWidget {
  const AccountTransitionOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final signingOut = context.select<AuthProvider, bool>(
      (auth) => auth.isSigningOut,
    );
    final signingIn = context.select<AuthProvider, bool>(
      (auth) => auth.isSigningIn,
    );
    final email = context.select<AuthProvider, String?>(
      (auth) => auth.signingInEmail,
    );

    final Widget? cover = signingOut
        ? const AccountTransitionView.signingOut(key: ValueKey<String>('out'))
        : signingIn
        ? AccountTransitionView.signingIn(
            key: ValueKey<String>('in:$email'),
            email: email,
          )
        : null;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        child,
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: cover ?? const SizedBox.shrink(),
        ),
      ],
    );
  }
}
