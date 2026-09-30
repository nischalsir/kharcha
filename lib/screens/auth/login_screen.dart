import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_failure.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/biometric_service.dart';
import '../../services/update_service.dart';
import '../../widgets/common/auth_widgets.dart';
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

  @override
  void initState() {
    super.initState();
    _restorePreferences();
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
    final String? savedEmail = await biometric.lastEmail();
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

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
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
      await _maybeSuggestBiometrics(biometric, email: email, password: password);
      if (mounted) {
        _returnToShell();
        // Check for updates after successful login
        unawaited(UpdateService().maybeShowUpdateDialog(context));
      }
    } catch (_) {
      // The failure is already exposed through AuthProvider.
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
    if (!_rememberMe || _biometricEnabled || !_capability.available) return;
    if (await biometric.wasSuggested()) return;
    await biometric.markSuggested();
    if (!mounted) return;

    final String kind = _capability.kind.label;
    final bool? enable = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.t('Enable $kind sign-in?', '$kind साइन इन सक्रिय गर्नुहुन्छ?'),
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
    if (!verified) return;
    await biometric.enable(email: email, password: password);
    if (mounted) setState(() => _biometricEnabled = true);
  }

  /// "Remember me" keeps the account in the encrypted vault so the next launch
  /// can prefill it and (when enabled) unlock with a fingerprint instead of
  /// typing the password again.
  Future<void> _persistLogin(
    BiometricService biometric, {
    required String email,
    required String password,
  }) async {
    await biometric.setRememberMe(_rememberMe);
    if (_rememberMe) {
      await biometric.saveCredentials(email: email, password: password);
    } else {
      await biometric.disable();
    }
  }

  Future<void> _handleBiometricSignIn() async {
    final AuthProvider auth = context.read<AuthProvider>();
    final BiometricService biometric = context.read<BiometricService>();

    final credentials = await biometric.readCredentials();
    if (credentials == null) {
      auth.setError(
        FailureKind.syncFailed,
        'No saved account. Sign in with your password first.',
      );
      return;
    }

    setState(() => _isLoading = true);
    auth.clearError();
    try {
      final bool verified = await biometric.authenticate(
        reason: 'Unlock your Kharcha account',
      );
      if (!verified) return;
      await auth.signIn(
        email: credentials.email,
        password: credentials.password,
      );
      if (mounted) _returnToShell();
    } catch (_) {
      // The failure is already exposed through AuthProvider.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogle() async {
    final AuthProvider auth = context.read<AuthProvider>();
    setState(() => _isLoading = true);
    try {
      await auth.signInWithGoogle();
      if (!mounted) return;
      _returnToShell();
      unawaited(UpdateService().maybeShowUpdateDialog(context));
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
      await auth.signInAnonymously();
      if (mounted) _returnToShell();
    } catch (error) {
      if (mounted) {
        auth.setError(FailureKind.syncFailed, AppFailure.from(error).message);
      }
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

  void _navigateToSignup() => Navigator.of(context).pushNamed(RoutePaths.signup);

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
        showMessage(context, 'Password reset link sent to $email');
      }
    } catch (error) {
      // Surfaced by AuthErrorBanner.
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
            const AuthErrorBanner(),
            GlassCard(
              radius: 28,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.email],
                    decoration: buildInputDecoration(
                      context,
                      label: context.t('Email', 'इमेल'),
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
                        return context.t('Enter a valid email', 'मान्य इमेल लेख्नुहोस्');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const <String>[AutofillHints.password],
                    decoration: buildInputDecoration(
                      context,
                      label: context.t('Password', 'पासवर्ड'),
                      hint: context.t('Enter your password', 'तपाईंको पासवर्ड लेख्नुहोस्'),
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
                        return context.t('Password is required', 'पासवर्ड आवश्यक छ');
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
            const SizedBox(height: 16),
            AuthGoogleButton(onPressed: _isLoading ? null : _handleGoogle),
            const SizedBox(height: 12),
            AuthGhostButton(
              label: context.t('Explore as guest', 'पाहुनाको रूपमा हेर्नुहोस्'),
              icon: Icons.visibility_outlined,
              tint: glass.textSecondary,
              onPressed: _isLoading ? null : _continueAsGuest,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
            TextButton(
              onPressed: _isLoading ? null : _requestPasswordReset,
              child: Text(
                context.t('Forgot password?', 'पासवर्ड बिर्सनुभयो?'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: glass.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for the email to send a reset link to.
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
        onSubmitted: (value) =>
            Navigator.of(context).pop(value.trim()),
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
          child: Text(context.t('Send link', 'लिंक पठाउनुहोस्')),
        ),
      ],
    );
  }
}
