import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../providers/auth_provider.dart';
import '../../services/sync_service.dart';
import '../../widgets/common/auth_widgets.dart';
import '../../widgets/common/email_code_dialog.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/common/glass_back_button.dart';

/// Turns a guest into a real account without losing anything they entered.
///
/// A new email converts the guest account in place (same user id, so every
/// record simply stays), after confirming a 6-digit code. An email that
/// already has an account instead signs in to it and moves the guest's
/// records across on the server.
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
  final TextEditingController _code = TextEditingController();

  bool _busy = false;
  bool _codeSent = false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final auth = context.read<AuthProvider>();
    setState(() => _busy = true);
    try {
      final name = _name.text.trim();
      final outcome = await auth.startGuestUpgrade(
        email: _email.text.trim(),
        fullName: name.isEmpty ? null : name,
      );
      if (!mounted) return;
      if (outcome == GuestUpgrade.codeSent) {
        setState(() => _codeSent = true);
      } else {
        await _offerMerge();
      }
    } catch (_) {
      // Surfaced through AuthFailureNotice.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 6) {
      showMessage(
        context,
        context.t('Enter the 6-digit code', '६ अंकको कोड लेख्नुहोस्'),
      );
      return;
    }
    final auth = context.read<AuthProvider>();
    setState(() => _busy = true);
    try {
      await auth.finishGuestUpgrade(
        email: _email.text.trim(),
        code: _code.text,
        password: _password.text,
      );
      if (!mounted) return;
      showMessage(
        context,
        context.t(
          'Your account is ready. All your data is saved.',
          'तपाईंको खाता तयार छ। सबै डाटा सुरक्षित छ।',
        ),
      );
      Navigator.of(context).pop();
    } catch (_) {
      // Surfaced through AuthFailureNotice.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _offerMerge() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          dialogContext.t(
            'You already have an account',
            'तपाईंको खाता पहिल्यै छ',
          ),
        ),
        content: Text(
          dialogContext.t(
            'Sign in to it with this password and move everything you added '
                'as a guest into it? Duplicate categories are merged.',
            'यही पासवर्डले साइन इन गरी पाहुनाको रूपमा थपेका सबै कुरा त्यो '
                'खातामा सार्ने? दोहोरिएका श्रेणीहरू मिलाइन्छन्।',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.t('Cancel', 'रद्द गर्नुहोस्')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              dialogContext.t('Sign in and move', 'साइन इन गरी सार्नुहोस्'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final auth = context.read<AuthProvider>();
    final sync = context.read<SyncService>();
    setState(() => _busy = true);
    try {
      // Anything still queued belongs to the guest; it must reach the server
      // before the claim, or it is left behind with the guest account.
      await sync.flushBeforeSignOut();
      final moved = await auth.mergeGuestIntoAccount(
        email: _email.text.trim(),
        password: _password.text,
      );
      // Signing in switched the cache to the account; pull what just moved.
      await sync.refresh();
      if (!mounted) return;
      showMessage(
        context,
        context.t(
          'Signed in. Moved $moved records from guest mode.',
          'साइन इन भयो। पाहुना मोडबाट $moved वटा रेकर्ड सारियो।',
        ),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          context.t(
            'Could not sign in. Check the password for that account.',
            'साइन इन हुन सकेन। त्यो खाताको पासवर्ड जाँच गर्नुहोस्।',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              subtitle: context.t(
                'Create an account to keep everything you added as a guest '
                    'and sync it across devices.',
                'पाहुनाको रूपमा थपेका सबै कुरा राख्न र अरू उपकरणमा सिङ्क '
                    'गर्न खाता बनाउनुहोस्।',
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
                children: _codeSent
                    ? _codeStep(context)
                    : _detailsStep(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _detailsStep(BuildContext context) {
    return <Widget>[
      TextFormField(
        controller: _name,
        textInputAction: TextInputAction.next,
        autofillHints: const <String>[AutofillHints.name],
        decoration: buildInputDecoration(
          context,
          label: context.t('Full name', 'पूरा नाम'),
          hint: context.t('Optional', 'ऐच्छिक'),
          prefixIcon: Icons.person_outline_rounded,
        ),
      ),
      const SizedBox(height: 14),
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
          if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(email)) {
            return context.t('Enter a valid email', 'मान्य इमेल लेख्नुहोस्');
          }
          return null;
        },
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: _password,
        obscureText: _obscure,
        textInputAction: TextInputAction.done,
        autofillHints: const <String>[AutofillHints.newPassword],
        onFieldSubmitted: (_) => _busy ? null : _continue(),
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
        label: context.t('Continue', 'अगाडि बढ्नुहोस्'),
        icon: Icons.arrow_forward_rounded,
        onPressed: _continue,
        isLoading: _busy,
      ),
    ];
  }

  List<Widget> _codeStep(BuildContext context) {
    final theme = Theme.of(context);
    return <Widget>[
      Text(
        context.t(
          'We sent a 6-digit code to ${_email.text.trim()}.',
          '${_email.text.trim()} मा ६ अंकको कोड पठाइयो।',
        ),
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 8),
      const SpamHint(),
      const SizedBox(height: 14),
      TextFormField(
        controller: _code,
        keyboardType: TextInputType.number,
        maxLength: 6,
        autofillHints: const <String>[AutofillHints.oneTimeCode],
        onFieldSubmitted: (_) => _busy ? null : _verify(),
        decoration: buildInputDecoration(
          context,
          label: context.t('Verification code', 'प्रमाणीकरण कोड'),
          prefixIcon: Icons.pin_outlined,
        ),
      ),
      const SizedBox(height: 12),
      PrimaryButton(
        label: context.t('Verify and save', 'प्रमाणित गरी सुरक्षित गर्नुहोस्'),
        icon: Icons.verified_rounded,
        onPressed: _verify,
        isLoading: _busy,
      ),
      TextButton(
        onPressed: _busy ? null : () => setState(() => _codeSent = false),
        child: Text(
          context.t('Use a different email', 'अर्को इमेल प्रयोग गर्नुहोस्'),
        ),
      ),
    ];
  }
}
