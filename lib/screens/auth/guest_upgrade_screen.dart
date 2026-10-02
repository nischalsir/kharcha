import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/auth_widgets.dart';
import '../../widgets/common/email_code_dialog.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/common/glass_back_button.dart';

/// Turns a guest into an account without losing what they entered.
///
/// A guest has no account anywhere: everything they added is on this phone.
/// Here they create an account, or sign in to one they already have, and what
/// they entered goes into it. Coming through this page is the guest saying
/// "keep my data", so the account is not asked about it again.
class GuestUpgradeScreen extends StatefulWidget {
  const GuestUpgradeScreen({super.key});

  @override
  State<GuestUpgradeScreen> createState() => _GuestUpgradeScreenState();
}

class _GuestUpgradeScreenState extends State<GuestUpgradeScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _busy = false;
  bool _obscure = true;

  /// Signing in to an account that already exists, rather than creating one.
  bool _existing = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Runs one way of getting an account. The guest's data is promised to it
  /// beforehand, and the promise is withdrawn if no account came of it.
  Future<void> _run(Future<bool> Function(AuthProvider auth) attempt) async {
    FocusScope.of(context).unfocus();
    final auth = context.read<AuthProvider>();
    final navigator = Navigator.of(context);
    auth
      ..clearError()
      ..keepGuestDataOnSignIn(true);
    setState(() => _busy = true);
    var done = false;
    try {
      done = await attempt(auth);
      // Back to the first page, where the account is loaded with what the
      // guest entered now part of it.
      if (done && navigator.mounted) {
        navigator.popUntil((route) => route.isFirst);
      }
    } catch (_) {
      // Shown from the bottom of the screen by AuthFailureNotice.
    } finally {
      if (!done) auth.keepGuestDataOnSignIn(null);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _email.text.trim();
    final password = _password.text;
    final name = _name.text.trim();
    await _run((auth) async {
      if (_existing) {
        try {
          await auth.signIn(email: email, password: password);
          return true;
        } catch (error) {
          if (!AuthProvider.isEmailNotConfirmed(error) || !mounted) rethrow;
          auth.clearError();
          return EmailCodeDialog.show(context, email: email, sendNow: true);
        }
      }
      await auth.signUp(email: email, password: password, fullName: name);
      if (auth.hasAccount) return true;
      // The email has to be confirmed with the code just sent to it;
      // entering it signs the new account in.
      if (!mounted) return false;
      return EmailCodeDialog.show(context, email: email);
    });
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
              title: context.t(
                'Save your data',
                'आफ्नो डाटा सुरक्षित गर्नुहोस्',
              ),
              subtitle: _existing
                  ? context.t(
                      'Sign in, and everything you added as a guest goes '
                          'into your account.',
                      'साइन इन गर्नुहोस्, पाहुनाको रूपमा थपेका सबै कुरा '
                          'तपाईंको खातामा जान्छ।',
                    )
                  : context.t(
                      'Create an account to keep everything you added as a '
                          'guest and sync it across devices.',
                      'पाहुनाको रूपमा थपेका सबै कुरा राख्न र अरू उपकरणमा '
                          'सिङ्क गर्न खाता बनाउनुहोस्।',
                    ),
              leading: Align(
                alignment: Alignment.centerLeft,
                child: GlassBackButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
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
                  if (!_existing) ...<Widget>[
                    TextFormField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const <String>[AutofillHints.name],
                      decoration: buildInputDecoration(
                        context,
                        label: context.t('Full name', 'पूरा नाम'),
                        prefixIcon: Icons.person_outline_rounded,
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? context.t(
                              'Full name is required',
                              'पूरा नाम आवश्यक छ',
                            )
                          : null,
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.email],
                    decoration: buildInputDecoration(
                      context,
                      label: context.t('Email', 'इमेल'),
                      prefixIcon: Icons.mail_outline_rounded,
                    ),
                    validator: (value) {
                      final email = (value ?? '').trim();
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
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    autofillHints: <String>[
                      _existing
                          ? AutofillHints.password
                          : AutofillHints.newPassword,
                    ],
                    onFieldSubmitted: (_) => _busy ? null : _submit(),
                    decoration: buildInputDecoration(
                      context,
                      label: context.t('Password', 'पासवर्ड'),
                      prefixIcon: Icons.lock_outline_rounded,
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => (value ?? '').length < 6
                        ? context.t('At least 6 characters', 'कम्तीमा ६ अक्षर')
                        : null,
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    key: const ValueKey<String>('guest-upgrade-submit'),
                    label: _existing
                        ? context.t(
                            'Sign in and keep my data',
                            'साइन इन गरी डाटा राख्नुहोस्',
                          )
                        : context.t('Create account', 'खाता बनाउनुहोस्'),
                    icon: Icons.arrow_forward_rounded,
                    onPressed: _submit,
                    isLoading: _busy,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              key: const ValueKey<String>('guest-upgrade-switch'),
              onPressed: _busy
                  ? null
                  : () => setState(() => _existing = !_existing),
              child: Text(
                _existing
                    ? context.t(
                        'New here? Create an account',
                        'नयाँ हुनुहुन्छ? खाता बनाउनुहोस्',
                      )
                    : context.t(
                        'I already have an account',
                        'मेरो खाता पहिल्यै छ',
                      ),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                context.t(
                  'Until then, what you add stays only on this phone.',
                  'त्यतिन्जेल तपाईंले थपेका कुरा यही फोनमा मात्र रहन्छ।',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
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
