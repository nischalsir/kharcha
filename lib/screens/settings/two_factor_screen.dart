import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/primary_button.dart';

/// Enroll and manage authenticator-app (TOTP) two-factor authentication.
class TwoFactorAuthScreen extends StatefulWidget {
  const TwoFactorAuthScreen({super.key});

  @override
  State<TwoFactorAuthScreen> createState() => _TwoFactorAuthScreenState();
}

class _TwoFactorAuthScreenState extends State<TwoFactorAuthScreen> {
  final TextEditingController _codeController = TextEditingController();
  AuthMFAEnrollResponse? _enrollment;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await context.read<AuthProvider>().refreshFactors();
  }

  Future<void> _startEnroll() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      await auth.clearUnverifiedTotpFactors();
      final response = await auth.startTotpEnrollment();
      if (!mounted) return;
      setState(() => _enrollment = response);
      await auth.refreshFactors();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmEnroll() async {
    final enrollment = _enrollment;
    if (enrollment == null || _busy) return;
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
      await context.read<AuthProvider>().confirmTotpEnrollment(
        factorId: enrollment.id,
        code: code,
      );
      if (!mounted) return;
      setState(() {
        _enrollment = null;
        _codeController.clear();
      });
      showMessage(
        context,
        context.t(
          'Two-factor authentication is now on.',
          'दुई-चरण प्रमाणीकरण अब सक्रिय छ।',
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelEnroll() async {
    final enrollment = _enrollment;
    setState(() {
      _enrollment = null;
      _error = null;
      _codeController.clear();
    });
    if (enrollment != null) {
      try {
        await context.read<AuthProvider>().disableFactor(enrollment.id);
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }

  Future<void> _disable() async {
    final auth = context.read<AuthProvider>();
    final factor = auth.verifiedFactors.isEmpty
        ? null
        : auth.verifiedFactors.first;
    if (factor == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.t('Turn off two-factor auth?', 'दुई-चरण प्रमाणीकरण बन्द गर्नुहुन्छ?'),
        ),
        content: Text(
          context.t(
            'You will only need your password to sign in again.',
            'फेरि साइन इन गर्दा पासवर्ड मात्र चाहिनेछ।',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t('Cancel', 'रद्द गर्नुहोस्')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.t('Turn off', 'बन्द गर्नुहोस्')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await auth.disableFactor(factor.id);
      if (mounted) {
        showMessage(
          context,
          context.t(
            'Two-factor authentication turned off.',
            'दुई-चरण प्रमाणीकरण बन्द गरियो।',
          ),
        );
      }
    } catch (error) {
      if (mounted) showMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();

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
            context.t('Two-factor authentication', 'दुई-चरण प्रमाणीकरण'),
            style: theme.textTheme.titleLarge,
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
            children: <Widget>[
              if (auth.hasMfaEnabled)
                ..._enabledContent(context, auth)
              else if (_enrollment != null)
                ..._enrollContent(context, _enrollment!)
              else
                ..._introContent(context),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _introContent(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return <Widget>[
      GlassCard(
        strong: true,
        glow: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.security_rounded, color: Color(0xFF30D158)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.t('Add an extra layer of security', 'सुरक्षाको थप तह थप्नुहोस्'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              context.t(
                'Use Google Authenticator (or any TOTP app) to generate a '
                    '6-digit code. You will enter it when you sign in.',
                'Google Authenticator (वा कुनै TOTP एप) प्रयोग गरी ६ अंकको कोड '
                    'बनाउनुहोस्। साइन इन गर्दा त्यो कोड लेख्नुपर्नेछ।',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: glass.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      PrimaryButton(
        label: context.t('Add authenticator app', 'प्रमाणक एप थप्नुहोस्'),
        icon: Icons.qr_code_2_rounded,
        onPressed: _busy ? null : _startEnroll,
        isLoading: _busy,
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
    ];
  }

  List<Widget> _enrollContent(BuildContext context, AuthMFAEnrollResponse e) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final secret = e.totp?.secret;
    final uri = e.totp?.uri;
    return <Widget>[
      Text(
        context.t('Scan this QR code', 'यो QR कोड स्क्यान गर्नुहोस्'),
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        context.t(
          'Open Google Authenticator, tap +, and scan the code below.',
          'Google Authenticator खोल्नुहोस्, + थिच्नुहोस्, र तलको कोड स्क्यान गर्नुहोस्।',
        ),
        style: theme.textTheme.bodySmall?.copyWith(color: glass.textSecondary),
      ),
      const SizedBox(height: 16),
      if (uri != null)
        Center(
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            child: ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: uri,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
        ),
      if (secret != null) ...<Widget>[
        const SizedBox(height: 16),
        Text(
          context.t(
            'Can’t scan? Enter this key manually:',
            'स्क्यान गर्न सकिएन? यो कुञ्जी म्यानुअल रूपमा लेख्नुहोस्:',
          ),
          style: theme.textTheme.bodySmall?.copyWith(color: glass.textSecondary),
        ),
        const SizedBox(height: 6),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: secret));
            if (context.mounted) {
              showMessage(
                context,
                context.t('Key copied to clipboard.', 'कुञ्जी क्लिपबोर्डमा प्रतिलिपि गरियो।'),
              );
            }
          },
          child: Row(
            children: <Widget>[
              Expanded(
                child: SelectableText(
                  secret,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Icon(Icons.copy_rounded, size: 16, color: glass.textTertiary),
            ],
          ),
        ),
      ],
      const SizedBox(height: 18),
      TextField(
        controller: _codeController,
        keyboardType: TextInputType.number,
        maxLength: 6,
        textAlign: TextAlign.center,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 6),
        decoration: buildInputDecoration(
          context,
          label: context.t('Enter the 6-digit code', '६ अंकको कोड लेख्नुहोस्'),
          hint: '000000',
          prefixIcon: Icons.pin_rounded,
        ).copyWith(counterText: ''),
      ),
      if (_error != null) ...<Widget>[
        const SizedBox(height: 8),
        Text(
          _error!,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ],
      const SizedBox(height: 16),
      PrimaryButton(
        label: context.t('Verify & enable', 'प्रमाणित गरी सक्रिय गर्नुहोस्'),
        icon: Icons.check_rounded,
        onPressed: _busy ? null : _confirmEnroll,
        isLoading: _busy,
      ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: _busy ? null : _cancelEnroll,
        child: Text(context.t('Cancel', 'रद्द गर्नुहोस्')),
      ),
    ];
  }

  List<Widget> _enabledContent(BuildContext context, AuthProvider auth) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return <Widget>[
      GlassCard(
        strong: true,
        glow: true,
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF30D158).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.verified_user_rounded,
                color: Color(0xFF30D158),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.t('Two-factor is on', 'दुई-चरण सक्रिय छ'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.t(
                      'You will be asked for a code when you sign in.',
                      'साइन इन गर्दा तपाईंलाई कोड सोधिनेछ।',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: glass.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      for (final factor in auth.verifiedFactors)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: <Widget>[
                const Icon(Icons.phonelink_lock_rounded, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    factor.friendlyName ??
                        context.t('Authenticator app', 'प्रमाणक एप'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _disable,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: Text(context.t('Turn off', 'बन्द गर्नुहोस्')),
                ),
              ],
            ),
          ),
        ),
      if (_error != null) ...<Widget>[
        const SizedBox(height: 4),
        Text(
          _error!,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ],
    ];
  }
}
