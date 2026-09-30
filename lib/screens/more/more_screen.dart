import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/auth_provider.dart';
import '../../screens/budgets/budgets_screen.dart';
import '../../screens/calculator/calculator_screen.dart';
import '../../screens/festivals/festivals_screen.dart';
import '../../screens/reports/reports_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../widgets/common/glass_card.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  String _themeLabel(BuildContext context, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return context.t('Light', 'उज्यालो');
      case ThemeMode.dark:
        return context.t('Dark', 'अँध्यारो');
      case ThemeMode.system:
        return context.t('System', 'प्रणाली');
    }
  }

  /// Logs the account out WITHOUT wiping the stored biometric credentials, so
  /// the fingerprint sign-in option stays available on the login screen.
  Future<void> _logout(BuildContext context) async {
    final AuthProvider auth = context.read<AuthProvider>();
    final NavigatorState navigator = Navigator.of(context);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.t('Log out?', 'लग आउट गर्नुहुन्छ?')),
        content: Text(
          context.t(
            'You will need to sign in again. Fingerprint sign-in stays on, '
            'so you can unlock with your fingerprint next time.',
            'तपाईंले फेरि साइन इन गर्नुपर्नेछ। फिंगरप्रिन्ट साइन इन '
            'सक्रिय रहनेछ, त्यसैले अर्को पटक फिंगरप्रिन्टबाटै खोल्न सक्नुहुन्छ।',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.t('Cancel', 'रद्द गर्नुहोस्')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.t('Log out', 'लग आउट')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await auth.signOut();
    } catch (_) {
      // The local session is dropped by the auth provider regardless.
    }
    // Drop any pushed routes so the auth wrapper's login page is what the
    // user lands on.
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = context.watch<AppSettingsProvider>().themeMode;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: <Widget>[
          Text(context.t('More', 'थप'), style: theme.textTheme.headlineMedium),
          const SizedBox(height: 16),
          _MoreTile(
            icon: Icons.account_balance_wallet_rounded,
            color: const Color(0xFF30D158),
            title: context.t('Budgets', 'बजेटहरू'),
            subtitle: context.t(
              'Monthly limits by category',
              'श्रेणी अनुसार मासिक सीमा',
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const BudgetsScreen()),
            ),
          ),
          _MoreTile(
            icon: Icons.celebration_rounded,
            color: const Color(0xFFFF9F0A),
            title: context.t('Festivals', 'चाडपर्वहरू'),
            subtitle: context.t(
              'Plan festival spending',
              'चाडपर्वको खर्च योजना बनाउनुहोस्',
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const FestivalsScreen()),
            ),
          ),
          _MoreTile(
            icon: Icons.bar_chart_rounded,
            color: const Color(0xFF0A84FF),
            title: context.t('Reports', 'प्रतिवेदनहरू'),
            subtitle: context.t(
              'Charts, PDF and CSV export',
              'चार्ट, PDF र CSV निर्यात',
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const ReportsScreen()),
            ),
          ),
          _MoreTile(
            icon: Icons.picture_as_pdf_rounded,
            color: const Color(0xFF64D2FF),
            title: context.t('Import PDF', 'PDF बाट आयात'),
            subtitle: context.t(
              'Add transactions from a bank statement',
              'बैंक स्टेटमेन्टबाट कारोबार थप्नुहोस्',
            ),
            onTap: () => Navigator.pushNamed(
              context,
              RoutePaths.statementImport,
            ),
          ),
          _MoreTile(
            icon: Icons.calculate_rounded,
            color: const Color(0xFFBF5AF2),
            title: context.t('Calculator', 'क्याल्कुलेटर'),
            subtitle: context.t('Quick calculations', 'द्रुत हिसाबकिताब'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const CalculatorScreen()),
            ),
          ),
          _MoreTile(
            icon: Icons.settings_rounded,
            color: const Color(0xFF8E8E93),
            title: context.t('Settings', 'सेटिङहरू'),
            subtitle: context.t(
              'Theme: ${_themeLabel(context, mode)}',
              'विषयवस्तु: ${_themeLabel(context, mode)}',
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
          _MoreTile(
            icon: Icons.logout_rounded,
            color: const Color(0xFFFF453A),
            title: context.t('Logout', 'लग आउट'),
            subtitle: context.t(
              'Sign out of this account',
              'यस खाताबाट साइन आउट गर्नुहोस्',
            ),
            onTap: () => _logout(context),
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        onTap: onTap,
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: theme.textTheme.titleMedium),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: glass.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: glass.textTertiary),
          ],
        ),
      ),
    );
  }
}
