import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/auth_widgets.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/primary_button.dart';

/// Second step of sign-in when the account has an authenticator app enrolled.
///
/// It is shown by the auth wrapper (not pushed) once a password sign-in has
/// succeeded but the session still needs to be promoted from AAL1 to AAL2.
class MfaChallengeScreen extends StatefulWidget {
  const MfaChallengeScreen({super.key});

  @override
  State<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends State<MfaChallengeScreen> {
  final TextEditingController _codeController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = context.t(
        'Enter the 6-digit code from your authenticator app',
        'तपाईंको प्रमाणक एपबाट ६ अंकको कोड लेख्नुहोस्',
      ));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().verifyMfa(code);
      // On success the wrapper rebuilds and shows the app shell.
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final auth = context.read<AuthProvider>();
    try {
      await auth.signOut();
    } catch (_) {
      // The wrapper falls back to the login screen regardless.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final email = context.watch<AuthProvider>().userEmail;

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AuthBrand(
            title: context.t('Two-factor verification', 'दुई-चरण प्रमाणीकरण'),
            subtitle: context.t(
              'Enter the 6-digit code from your authenticator app to finish '
                  'signing in.',
              'साइन इन पूरा गर्न तपाईंको प्रमाणक एपबाट ६ अंकको कोड लेख्नुहोस्।',
            ),
          ),
          const SizedBox(height: 24),
          if (email != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                email,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: glass.textSecondary,
                ),
              ),
            ),
          GlassCard(
            radius: 28,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: _codeController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: theme.textTheme.headlineSmall?.copyWith(
                    letterSpacing: 8,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: buildInputDecoration(
                    context,
                    label: context.t('Authentication code', 'प्रमाणीकरण कोड'),
                    hint: '000000',
                    prefixIcon: Icons.pin_rounded,
                  ).copyWith(counterText: ''),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                PrimaryButton(
                  label: context.t('Verify', 'प्रमाणित गर्नुहोस्'),
                  icon: Icons.verified_rounded,
                  onPressed: _busy ? null : _submit,
                  isLoading: _busy,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AuthGhostButton(
            label: context.t('Sign out', 'साइन आउट'),
            icon: Icons.logout_rounded,
            tint: glass.textSecondary,
            onPressed: _busy ? null : _signOut,
          ),
        ],
      ),
    );
  }
}
