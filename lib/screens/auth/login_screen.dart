import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_failure.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/account_avatar_cache.dart';
import '../../services/biometric_service.dart';
import '../../services/google_account.dart';
import '../../widgets/common/auth_widgets.dart';
import '../../widgets/common/email_code_dialog.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/primary_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = true;
  bool _biometricEnabled = false;
  BiometricCapability _capability = BiometricCapability.none;

  /// Whether this build can sign in with Google at all.
  bool _googleReady = false;

  @override
  void initState() {
    super.initState();
    _restorePreferences();
    GoogleAccount.isConfigured().then((ready) {
      if (mounted && ready) setState(() => _googleReady = true);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Restores the remembered account and works out whether the biometric
  /// button should be offered on this device.
  Future<void> _restorePreferences() async {
    final BiometricService biometric = context.read<BiometricService>();
    final BiometricCapability capability = await biometric.capability();
    final bool remember = await biometric.rememberMe();
    final bool enabled = await biometric.isEnabled();
    final String? savedEmail = await biometric.rememberedEmail();
    if (!mounted) return;
    setState(() {
      _capability = capability;
      _rememberMe = remember;
      _biometricEnabled = enabled && capability.available;
      if (savedEmail != null) _emailController.text = savedEmail;
    });
  }

  /// Whether to *show* the biometric button. Deliberately independent of
  /// [_isLoading]: tying visibility to it removed the button the instant it
  /// was tapped, while the fingerprint prompt was still on screen. Loading now
  /// only disables it.
  bool get _canUseBiometrics => _capability.available && _biometricEnabled;

  /// What is wrong with what was typed, or null when it can be sent.
  String? _problem() {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      return context.t('Enter your email', 'आफ्नो इमेल लेख्नुहोस्');
    }
    if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(email)) {
      return context.t(
        'That email does not look right. Check it and try again.',
        'त्यो इमेल ठीक देखिएन। जाँचेर फेरि प्रयास गर्नुहोस्।',
      );
    }
    final password = _passwordController.text;
    if (password.isEmpty) {
      return context.t('Enter your password', 'आफ्नो पासवर्ड लेख्नुहोस्');
    }
    if (password.length < 6) {
      return context.t(
        'Passwords have at least 6 characters',
        'पासवर्ड कम्तीमा ६ अक्षरको हुन्छ',
      );
    }
    return null;
  }

  Future<void> _handleLogin() async {
    // The fields are marked, and what is wrong is said in a notice from the
    // bottom of the screen, the same place every other sign-in problem goes.
    final valid = _formKey.currentState!.validate();
    final problem = _problem();
    if (!valid || problem != null) {
      if (problem != null) showAuthNotice(context, problem);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final AuthProvider auth = context.read<AuthProvider>();
    final BiometricService biometric = context.read<BiometricService>();
    auth.clearError();

    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    try {
      await auth.signIn(email: email, password: password);
      await _persistLogin(biometric, email: email, password: password);
      await _maybeSuggestBiometrics(
        biometric,
        email: email,
        password: password,
      );
      if (mounted) _returnToShell();
    } catch (error) {
      // The failure is already exposed through AuthProvider. An account
      // whose sign-up code was never entered gets a fresh code and the box
      // to enter it in, instead of a dead end.
      if (AuthProvider.isEmailNotConfirmed(error) && mounted) {
        auth.clearError();
        final confirmed = await EmailCodeDialog.show(
          context,
          email: email,
          sendNow: true,
        );
        if (confirmed) {
          await _persistLogin(biometric, email: email, password: password);
          if (mounted) _returnToShell();
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// One-time offer to switch on fingerprint/face unlock right after a
  /// successful password sign-in. Until this (or the Settings toggle) enables
  /// biometric sign-in, the login screen hides the biometric button on purpose.
  Future<void> _maybeSuggestBiometrics(
    BiometricService biometric, {
    required String email,
    required String password,
  }) async {
    if (!_rememberMe || !_capability.available) return;
    if (await biometric.isEnabledFor(email)) return;
    if (await biometric.wasSuggested()) return;
    await biometric.markSuggested();
    if (!mounted) return;

    final String kind = _capability.kind.label;
    final bool? enable = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.t(
            'Enable $kind sign-in?',
            '$kind साइन इन सक्रिय गर्नुहुन्छ?',
          ),
        ),
        content: Text(
          context.t(
            'Next time you can unlock Kharcha with '
                '${kind.toLowerCase()} instead of typing your password.',
            'अर्को पटक पासवर्ड टाइप नगरी '
                '${kind.toLowerCase()} बाटै खर्चा खोल्न सक्नुहुन्छ।',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t('Not now', 'अहिले होइन')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t('Enable', 'सक्रिय गर्नुहोस्')),
          ),
        ],
      ),
    );
    if (enable != true || !mounted) return;

    final bool verified = await biometric.authenticate(
      reason: 'Enable $kind sign-in',
    );
    if (!verified || !mounted) return;
    // Only an account that has finished signing in, authenticator code
    // included, may later use the fingerprint in place of that code.
    final bool fullySignedIn = !context.read<AuthProvider>().mfaPending;
    await biometric.enable(
      email: email,
      password: password,
      trusted: fullySignedIn,
    );
    if (mounted) setState(() => _biometricEnabled = true);
  }

  /// Records who just signed in: the email to prefill next time, and a fresh
  /// password for this account's fingerprint entry if it has one. Each is
  /// keyed to this account, so another account's entries are never touched.
  Future<void> _persistLogin(
    BiometricService biometric, {
    required String email,
    required String password,
  }) async {
    await biometric.setRememberMe(_rememberMe);
    if (_rememberMe) {
      await biometric.setRememberedEmail(email);
      await biometric.updatePassword(email: email, password: password);
    } else {
      await biometric.setRememberedEmail(null);
      await biometric.disable(email);
    }
  }

  Future<void> _handleBiometricSignIn() async {
    final AuthProvider auth = context.read<AuthProvider>();
    final BiometricService biometric = context.read<BiometricService>();

    final accounts = await biometric.accounts();
    if (accounts.isEmpty) {
      auth.setError(
        FailureKind.syncFailed,
        'No saved account. Sign in with your password first.',
      );
      if (mounted) setState(() => _biometricEnabled = false);
      return;
    }

    setState(() => _isLoading = true);
    auth.clearError();
    BiometricAccount? account;
    try {
      final bool verified = await biometric.authenticate(
        reason: 'Unlock your Kharcha account',
      );
      if (!verified || !mounted) return;
      // The fingerprint proves who holds the phone, not which account they
      // mean, so with several accounts the user has to say.
      // Each account's own saved picture, looked up by that account's email.
      final avatars = <String, ImageProvider>{};
      if (accounts.length > 1) {
        final cache = context.read<AccountAvatarCache>();
        for (final entry in accounts) {
          final file = await cache.fileFor(entry.email);
          if (file != null) avatars[entry.email] = FileImage(file);
        }
        if (!mounted) return;
      }
      account = await chooseBiometricAccount(
        context,
        accounts,
        avatarFor: (entry) => avatars[entry.email],
      );
      if (account == null) return;
      await auth.signIn(
        email: account.email,
        password: account.password,
        trustedDevice: account.trusted,
      );
      if (await biometric.rememberMe()) {
        await biometric.setRememberedEmail(account.email);
      }
      if (mounted) _returnToShell();
    } catch (error) {
      // The failure is already exposed through AuthProvider. A password that
      // was changed elsewhere can never work again, so that entry is removed
      // rather than left to fail on every tap.
      if (account != null && AuthProvider.isWrongCredentials(error)) {
        await biometric.disable(account.email);
        if (mounted) {
          unawaited(context.read<AccountAvatarCache>().remove(account.email));
        }
        final bool any = await biometric.isEnabled();
        if (mounted) {
          setState(() => _biometricEnabled = any);
          auth.setError(
            FailureKind.syncFailed,
            'The saved password for ${account.email} no longer works. '
            'Sign in with your password.',
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final AuthProvider auth = context.read<AuthProvider>();
    final BiometricService biometric = context.read<BiometricService>();
    auth.clearError();

    try {
      await auth.signInWithGoogle();
      final String? email = auth.userEmail;
      if (email != null && await biometric.rememberMe()) {
        await biometric.setRememberedEmail(email);
      }
      if (mounted) _returnToShell();
    } catch (_) {
      // The failure is already exposed through AuthProvider.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _continueAsGuest() async {
    final AuthProvider auth = context.read<AuthProvider>();
    setState(() => _isLoading = true);
    auth.clearError();
    try {
      // Nothing is asked of the server: a guest's data stays on this phone.
      await auth.continueAsGuest();
      if (mounted) _returnToShell();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Unwinds to the root route so `_AuthWrapper` can decide what to show.
  /// Pushing a second shell would leave the auth wrapper outside the navigator
  /// stack, which breaks the sign-out path.
  void _returnToShell() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _navigateToSignup() =>
      Navigator.of(context).pushNamed(RoutePaths.signup);

  Future<void> _requestPasswordReset() async {
    final NavigatorState navigator = Navigator.of(context);
    final String? email = await showDialog<String>(
      context: context,
      builder: (_) =>
          _ResetPasswordDialog(initial: _emailController.text.trim()),
    );
    if (email == null || email.isEmpty || !navigator.mounted) return;

    final AuthProvider auth = context.read<AuthProvider>();
    try {
      await auth.resetPassword(email);
      if (navigator.mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => _ResetPasswordCodeDialog(email: email),
        );
      }
    } catch (_) {
      // Surfaced by AuthFailureNotice.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;

    return AuthScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AuthBrand(
              title: context.t('Welcome back', 'पुनः स्वागत छ'),
              subtitle: context.t(
                'Sign in to keep tracking where your money goes.',
                'तपाईंको पैसा कहाँ जान्छ भनेर ट्र्याक गर्न साइन इन गर्नुहोस्।',
              ),
            ),
            const SizedBox(height: 28),
            const AuthFailureNotice(),
            GlassCard(
              radius: 28,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _FieldLabel(context.t('Email', 'इमेल')),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.email],
                    decoration: buildInputDecoration(
                      context,
                      hint: 'you@example.com',
                      prefixIcon: Icons.email_outlined,
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty) {
                        return context.t('Email is required', 'इमेल आवश्यक छ');
                      }
                      if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,}$')
                          .hasMatch(email)) {
                        return context.t(
                          'Enter a valid email',
                          'मान्य इमेल लेख्नुहोस्',
                        );
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  // "Password" and the way out of having forgotten it, on
                  // one line, right above the field they are about.
                  _FieldLabel(
                    context.t('Password', 'पासवर्ड'),
                    trailing: TextButton(
                      key: const ValueKey<String>('login-forgot'),
                      onPressed: _isLoading ? null : _requestPasswordReset,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.primary,
                        // Tall enough to tap, without pushing the row apart.
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        context.t('Forgot password?', 'पासवर्ड बिर्सनुभयो?'),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const <String>[AutofillHints.password],
                    decoration: buildInputDecoration(
                      context,
                      hint: context.t(
                        'Enter your password',
                        'तपाईंको पासवर्ड लेख्नुहोस्',
                      ),
                      prefixIcon: Icons.lock_outline_rounded,
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? context.t('Show', 'देखाउनुहोस्')
                            : context.t('Hide', 'लुकाउनुहोस्'),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                    validator: (value) {
                      final password = value ?? '';
                      if (password.isEmpty) {
                        return context.t(
                          'Password is required',
                          'पासवर्ड आवश्यक छ',
                        );
                      }
                      if (password.length < 6) {
                        return context.t(
                          'Password must be at least 6 characters',
                          'पासवर्ड कम्तीमा ६ अक्षरको हुनुपर्छ',
                        );
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _handleLogin(),
                  ),
                  const SizedBox(height: 8),
                  AuthSwitchRow(
                    label: context.t('Remember me', 'मलाई सम्झनुहोस्'),
                    subtitle: context.t(
                      'Stay signed in on this device',
                      'यो उपकरणमा साइन इन रहनुहोस्',
                    ),
                    icon: Icons.person_pin_circle_rounded,
                    value: _rememberMe,
                    onChanged: (value) {
                      setState(() => _rememberMe = value);
                      context.read<BiometricService>().setRememberMe(value);
                    },
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: context.t('Sign In', 'साइन इन'),
                    icon: Icons.arrow_forward_rounded,
                    onPressed: _handleLogin,
                    isLoading: _isLoading,
                  ),
                  if (_canUseBiometrics) ...<Widget>[
                    const SizedBox(height: 12),
                    AuthGhostButton(
                      label: context.t(
                        'Sign in with ${_capability.kind.label}',
                        '${_capability.kind.label} बाट साइन इन',
                      ),
                      icon: _capability.kind.icon,
                      onPressed: _isLoading ? null : _handleBiometricSignIn,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_googleReady) ...<Widget>[
              GoogleSignInButton(
                onPressed: _isLoading ? null : _handleGoogleSignIn,
              ),
              const SizedBox(height: 12),
            ],
            AuthGhostButton(
              label: context.t('Explore as guest', 'पाहुनाको रूपमा हेर्नुहोस्'),
              icon: Icons.visibility_outlined,
              tint: glass.textSecondary,
              onPressed: _isLoading ? null : _continueAsGuest,
            ),
            const SizedBox(height: 20),
            // Wraps onto a second line on a narrow screen or with large text,
            // where a Row would run off the edge.
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  context.t('New to Kharcha?', 'खर्चामा नयाँ हुनुहुन्छ?'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: glass.textSecondary,
                  ),
                ),
                TextButton(
                  onPressed: _navigateToSignup,
                  child: Text(
                    context.t('Create account', 'खाता बनाउनुहोस्'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The name of a field, written above it, with room at the end of the line
/// for something that belongs to that field.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 0, 0, trailing == null ? 8 : 0),
      child: Row(
        children: <Widget>[
          Text(
            text,
            maxLines: 1,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          // At the far end of the line. On a very narrow phone, or with very
          // large text, it shrinks to fit rather than running off the edge.
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: trailing == null
                  ? null
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: trailing,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for the email to send a reset code to.
///
/// This owns its [TextEditingController] on purpose. Disposing the controller
/// in the caller's `finally` would do it while the dialog is still animating
/// out, and the still-attached [TextField] would then read a disposed
/// controller — which crashes to a red screen on Cancel.
class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.initial});

  final String initial;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.t('Reset password', 'पासवर्ड रिसेट')),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        decoration: InputDecoration(
          labelText: context.t('Email', 'इमेल'),
          hintText: 'you@example.com',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('Cancel', 'रद्द गर्नुहोस्')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(context.t('Send code', 'कोड पठाउनुहोस्')),
        ),
      ],
    );
  }
}

class _ResetPasswordCodeDialog extends StatefulWidget {
  const _ResetPasswordCodeDialog({required this.email});

  final String email;

  @override
  State<_ResetPasswordCodeDialog> createState() =>
      _ResetPasswordCodeDialogState();
}

class _ResetPasswordCodeDialogState extends State<_ResetPasswordCodeDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _busy = false;
  bool _obscurePassword = true;

  /// The password the server refused for being the same as the old one.
  String? _rejectedPassword;

  String? _sameAsOld(String? value) {
    if (_rejectedPassword == null || value != _rejectedPassword) return null;
    return context.t(
      'New password must be different from old password',
      'नयाँ पासवर्ड पुरानो पासवर्डबाट फरक हुनुपर्छ',
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);

    try {
      await context.read<AuthProvider>().resetPasswordWithCode(
        email: widget.email,
        code: _codeController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessage(
        context,
        context.t(
          'Password updated. You can now sign in.',
          'पासवर्ड अद्यावधिक गरियो। अब साइन इन गर्नुहोस्।',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      if (AuthProvider.isSamePasswordError(error)) {
        // The old password is not typed here, so only the server can tell.
        // Mark the two new-password fields rather than a banner behind the dialog.
        setState(() => _rejectedPassword = _passwordController.text);
        _formKey.currentState!.validate();
      } else {
        showMessage(context, context.read<AuthProvider>().error ?? '$error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.t('Enter reset code', 'रिसेट कोड लेख्नुहोस्')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                context.t(
                  'Enter the 6-digit code sent to ${widget.email}.',
                  '${widget.email} मा पठाइएको ६ अंकको कोड लेख्नुहोस्।',
                ),
              ),
              const SizedBox(height: 8),
              const SpamHint(),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codeController,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: context.t('Reset code', 'रिसेट कोड'),
                  hintText: '000000',
                  counterText: '',
                ),
                validator: (value) {
                  if (!RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')) {
                    return context.t(
                      'Enter the 6-digit code',
                      '६ अंकको कोड लेख्नुहोस्',
                    );
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: context.t('New password', 'नयाँ पासवर्ड'),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (value) {
                  if ((value ?? '').length < 6) {
                    return context.t(
                      'Password must be at least 6 characters',
                      'पासवर्ड कम्तीमा ६ अक्षरको हुनुपर्छ',
                    );
                  }
                  return _sameAsOld(value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: context.t(
                    'Confirm new password',
                    'नयाँ पासवर्ड पुष्टि गर्नुहोस्',
                  ),
                ),
                validator: (value) => value == _passwordController.text
                    ? _sameAsOld(value)
                    : context.t('Passwords do not match', 'पासवर्डहरू मिलेनन्'),
                onFieldSubmitted: (_) => _resetPassword(),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(context.t('Cancel', 'रद्द गर्नुहोस्')),
        ),
        FilledButton(
          onPressed: _busy ? null : _resetPassword,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.t('Reset password', 'पासवर्ड रिसेट')),
        ),
      ],
    );
  }
}
