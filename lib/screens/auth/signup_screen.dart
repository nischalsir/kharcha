import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_failure.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/biometric_service.dart';
import '../../services/update_service.dart';
import '../../widgets/common/auth_widgets.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/pressable_scale.dart';
import '../../widgets/common/primary_button.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _agreeToTerms = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreeToTerms) {
      context.read<AuthProvider>().setError(
        FailureKind.invalidData,
        context.t(
          'Please agree to the Terms of Service',
          'कृपया सेवा शर्तहरूमा सहमत हुनुहोस्',
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final AuthProvider auth = context.read<AuthProvider>();
    auth.clearError();

    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    try {
      await auth.signUp(
        email: email,
        password: password,
        fullName: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
      );

      if (!mounted) return;
      if (auth.session == null) {
        _showVerificationDialog();
        return;
      }

      await _suggestBiometrics(email: email, password: password);
      if (mounted) {
        _returnToShell();
        unawaited(UpdateService().maybeShowUpdateDialog(context));
      }
    } catch (_) {
      // The failure is already exposed through AuthProvider.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Once per account creation, offer to store the credentials behind the
  /// fingerprint so the next launch is a single tap.
  Future<void> _suggestBiometrics({
    required String email,
    required String password,
  }) async {
    final BiometricService biometric = context.read<BiometricService>();
    final BiometricCapability capability = await biometric.capability();
    if (!capability.available) return;
    if (await biometric.wasSuggested()) return;
    await biometric.markSuggested();
    if (!mounted) return;

    final bool? enable = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign in faster next time'),
        content: Text(
          'Turn on ${capability.kind.label.toLowerCase()} sign-in and Kharcha will '
          'unlock with a single tap instead of your password.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );

    if (enable != true) return;
    await biometric.enable(email: email, password: password);
  }

  /// Unwinds to the root route so `_AuthWrapper` can decide what to show
  /// (the shell when signed in, the login page when not).
  void _returnToShell() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _showTermsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Terms of Service', 'सेवा शर्तहरू')),
        content: SingleChildScrollView(
          child: Text(
            context.t(
              'Terms of Service\n\n'
                  '1. Acceptance of Terms\n'
                  'By using Kharcha, you agree to these terms and conditions.\n\n'
                  '2. User Responsibilities\n'
                  'You are responsible for maintaining the confidentiality of your account and password. '
                  'You agree to accept responsibility for all activities that occur under your account.\n\n'
                  '3. Data Privacy\n'
                  'Guest mode data is stored only on your device. Once you upgrade to a registered account, '
                  'your data is securely stored on our servers.\n\n'
                  '4. Limitation of Liability\n'
                  'Kharcha is provided "as is" without warranties. We are not liable for any data loss or service interruptions.\n\n'
                  '5. Changes to Terms\n'
                  'We reserve the right to modify these terms at any time.',
              'सेवा शर्तहरू\n\n'
                  '1. शर्तहरू स्वीकार गर्ने\n'
                  'खर्चा प्रयोग गरेर, तपाईं यी शर्तहरू स्वीकार गर्नुहुन्छ।\n\n'
                  '2. प्रयोगकर्ताको दायित्व\n'
                  'आपफ्नो खाता र पासवर्डको गोपनीयता बनाए राख्न आपण जिम्मेवार हुनुहुन्छ।\n\n'
                  '3. डेटा गोपनीयता\n'
                  'अतिथि मोडको डेटा केवल तपाईंको उपकरणमा संग्रहीत हुन्छ।\n\n'
                  '4. दायित्वको सीमा\n'
                  'खर्चा "जस्तो छ" प्रदान गरिन्छ।\n\n'
                  '5. शर्तहरूमा परिवर्तन\n'
                  'हामीले कुनै पनी समयमा शर्तहरू परिवर्तन गर्न सकार्छ।',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('Close', 'बन्द गर्नुहोस्')),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Privacy Policy', 'गोपनीयता नीति')),
        content: SingleChildScrollView(
          child: Text(
            context.t(
              'Privacy Policy\n\n'
                  '1. Information We Collect\n'
                  'We collect information you provide directly, such as your email, name, and expense data.\n\n'
                  '2. How We Use Information\n'
                  'Your data is used to provide and improve the Kharcha service. We do not sell your data.\n\n'
                  '3. Data Security\n'
                  'We use industry-standard encryption to protect your data. All communications are secure.\n\n'
                  '4. Third-Party Services\n'
                  'Kharcha uses Supabase for authentication and data storage. '
                  'Please review their privacy policy as well.\n\n'
                  '5. Contact Us\n'
                  'If you have privacy concerns, please contact us through the app.',
              'गोपनीयता नीति\n\n'
                  '1. हामीले संग्रह गरेको जानकारी\n'
                  'हामीले तपाईंको इमेल, नाम र खर्च डेटा संग्रह गरी।\n\n'
                  '2. जानकारी कसरी प्रयोग गरिन्छ\n'
                  'तपाईंको डेटा खर्चा सेवा प्रदान गर्न प्रयोग गरिन्छ।\n\n'
                  '3. डेटा सुरक्षा\n'
                  'हामीले आपफ्नो डेटा सुरक्षित गर्न एन्क्रिप्शन प्रयोग गरी।\n\n'
                  '4. तेस्रो पक्षको सेवा\n'
                  'खर्चा Supabase प्रयोग गर्दछ।\n\n'
                  '5. हामीसँग संपर्क गर्नुहोस्\n'
                  'यदि कुनै गोपनीयता चिन्ता छ भने कृपया संपर्क गर्नुहोस्।',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('Close', 'बन्द गर्नुहोस्')),
          ),
        ],
      ),
    );
  }

  void _showVerificationDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.t('Verify your email', 'तपाईंको इमेल सत्यापन गर्नुहोस्'),
        ),
        content: Text(
          context.t(
            'We sent a verification link to your inbox. Open it to activate your '
                'account, then come back and sign in.',
            'हामीले तपाईंको इनबक्समा सत्यापन लिङ्क पठाएका छौं। आफ्नो खाता सक्रिय गर्न '
                'उसे खोल्नुहोस्, भनेर फेरि आउनुहोस् र साइन इन गर्नुहोस्।',
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('OK', 'ठिक छ')),
          ),
        ],
      ),
    );
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
                'Create your account',
                'तपाईंको खाता बनाउनुहोस्',
              ),
              subtitle: context.t(
                'Start tracking expenses, budgets and shared costs.',
                'खर्च, बजेट र साझा लागतहरू ट्र्याक गर्न सुरु गर्नुहोस्।',
              ),
              leading: Align(
                alignment: Alignment.centerLeft,
                child: PressableScale(
                  onTap: _returnToShell,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: glass.fill,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
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
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.name],
                    decoration: buildInputDecoration(
                      context,
                      label: 'Full name',
                      hint: 'Optional',
                      prefixIcon: Icons.person_outline_rounded,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.email],
                    decoration: buildInputDecoration(
                      context,
                      label: 'Email',
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
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.newPassword],
                    decoration: buildInputDecoration(
                      context,
                      label: 'Password',
                      hint: 'At least 6 characters',
                      prefixIcon: Icons.lock_outline_rounded,
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? 'Show' : 'Hide',
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
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const <String>[AutofillHints.newPassword],
                    decoration: buildInputDecoration(
                      context,
                      label: 'Confirm password',
                      hint: 'Re-enter your password',
                      prefixIcon: Icons.lock_reset_rounded,
                      suffixIcon: IconButton(
                        tooltip: _obscureConfirmPassword ? 'Show' : 'Hide',
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () => setState(
                          () => _obscureConfirmPassword =
                              !_obscureConfirmPassword,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return context.t(
                          'Please confirm your password',
                          'कृपया पासवर्ड पुष्टि गर्नुहोस्',
                        );
                      }
                      if (value != _passwordController.text) {
                        return context.t(
                          'Passwords do not match',
                          'पासवर्ड मिल्दैन',
                        );
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _handleSignup(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _agreeToTerms,
                          onChanged: (value) =>
                              setState(() => _agreeToTerms = value ?? false),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text.rich(
                            TextSpan(
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: glass.textSecondary,
                                height: 1.4,
                              ),
                              children: <InlineSpan>[
                                TextSpan(
                                  text: context.t('I agree to the ', 'म '),
                                ),
                                WidgetSpan(
                                  child: GestureDetector(
                                    onTap: () => _showTermsDialog(context),
                                    child: Text(
                                      context.t('Terms', 'शर्तहरू'),
                                      style: TextStyle(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                                TextSpan(text: context.t(' and ', ' र ')),
                                WidgetSpan(
                                  child: GestureDetector(
                                    onTap: () => _showPrivacyDialog(context),
                                    child: Text(
                                      context.t(
                                        'Privacy Policy',
                                        'गोपनीयता नीति',
                                      ),
                                      style: TextStyle(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  PrimaryButton(
                    label: context.t('Create account', 'खाता बनाउनुहोस्'),
                    icon: Icons.check_rounded,
                    onPressed: _handleSignup,
                    isLoading: _isLoading,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  context.t('Already have an account?', 'पहिले नै खाता छ?'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: glass.textSecondary,
                  ),
                ),
                TextButton(
                  onPressed: _returnToShell,
                  child: Text(
                    context.t('Sign in', 'साइन इन'),
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
