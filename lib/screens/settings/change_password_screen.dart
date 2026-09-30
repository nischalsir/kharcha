import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/primary_button.dart';

/// Change the account password.
///
/// When two-factor authentication is on, the current authenticator code must be
/// verified first (which also promotes the session to AAL2).
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _currentController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _currentController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final needsCode = auth.hasMfaEnabled;
    if (needsCode && _codeController.text.trim().length != 6) {
      showMessage(
        context,
        context.t(
          'Enter the 6-digit code from your authenticator app',
          'तपाईंको प्रमाणक एपबाट ६ अंकको कोड लेख्नुहोस्',
        ),
      );
      return;
    }

    setState(() => _busy = true);
    auth.clearError();
    try {
      // Prove the current password first: Supabase would otherwise let anyone
      // holding a live session change the password without ever knowing it.
      await auth.verifyCurrentPassword(_currentController.text);
      if (needsCode) {
        await auth.verifyMfa(_codeController.text.trim());
      }
      await auth.updatePassword(_passwordController.text);
      if (!mounted) return;
      showMessage(
        context,
        context.t('Password updated.', 'पासवर्ड अद्यावधिक गरियो।'),
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) showMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final needsCode = context.watch<AuthProvider>().hasMfaEnabled;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: theme.colorScheme.onSurface,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            context.t('Change password', 'पासवर्ड परिवर्तन गर्नुहोस्'),
            style: theme.textTheme.titleLarge,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (needsCode) ...<Widget>[
                    Text(
                      context.t(
                        'Two-factor is on — verify your code to continue.',
                        'दुई-चरण सक्रिय छ — जारी राख्न कोड प्रमाणित गर्नुहोस्।',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: glass.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      child: TextFormField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: buildInputDecoration(
                          context,
                          label: context.t(
                            'Authentication code',
                            'प्रमाणीकरण कोड',
                          ),
                          hint: '000000',
                          prefixIcon: Icons.pin_rounded,
                        ).copyWith(counterText: ''),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  GlassCard(
                    child: Column(
                      children: <Widget>[
                        TextFormField(
                          controller: _currentController,
                          obscureText: _obscureCurrent,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const <String>[AutofillHints.password],
                          decoration: buildInputDecoration(
                            context,
                            label: context.t(
                              'Old password',
                              'पुरानो पासवर्ड',
                            ),
                            hint: context.t(
                              'Enter your current password',
                              'आफ्नो हालको पासवर्ड लेख्नुहोस्',
                            ),
                            prefixIcon: Icons.lock_outline_rounded,
                            suffixIcon: IconButton(
                              tooltip: _obscureCurrent
                                  ? context.t('Show', 'देखाउनुहोस्')
                                  : context.t('Hide', 'लुकाउनुहोस्'),
                              icon: Icon(
                                _obscureCurrent
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              onPressed: () =>
                                  setState(() => _obscureCurrent = !_obscureCurrent),
                            ),
                          ),
                          validator: (value) {
                            final current = value ?? '';
                            if (current.isEmpty) {
                              return context.t(
                                'Old password is required',
                                'पुरानो पासवर्ड आवश्यक छ',
                              );
                            }
                            if (current == _passwordController.text) {
                              return context.t(
                                'New password must be different',
                                'नयाँ पासवर्ड फरक हुनुपर्छ',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscure,
                          decoration: buildInputDecoration(
                            context,
                            label: context.t('New password', 'नयाँ पासवर्ड'),
                            hint: context.t(
                              'At least 6 characters',
                              'कम्तीमा ६ अक्षर',
                            ),
                            prefixIcon: Icons.lock_outline_rounded,
                            suffixIcon: IconButton(
                              tooltip: _obscure
                                  ? context.t('Show', 'देखाउनुहोस्')
                                  : context.t('Hide', 'लुकाउनुहोस्'),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
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
                          controller: _confirmController,
                          obscureText: _obscure,
                          decoration: buildInputDecoration(
                            context,
                            label: context.t(
                              'Confirm new password',
                              'नयाँ पासवर्ड पुष्टि गर्नुहोस्',
                            ),
                            prefixIcon: Icons.lock_reset_rounded,
                          ),
                          validator: (value) {
                            if (value != _passwordController.text) {
                              return context.t(
                                'Passwords do not match',
                                'पासवर्डहरू मिलेनन्',
                              );
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: context.t('Update password', 'पासवर्ड अद्यावधिक गर्नुहोस्'),
                    icon: Icons.check_rounded,
                    onPressed: _busy ? null : _save,
                    isLoading: _busy,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
