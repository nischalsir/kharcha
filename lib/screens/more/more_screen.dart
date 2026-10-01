import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_info.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/update_provider.dart';
import '../../widgets/common/glass_card.dart';
import '../auth/guest_upgrade_screen.dart';

/// Everything that does not have its own tab, in three groups:
///
///   * **Plan & track** - budgets, reports and the calendar: looking at money;
///   * **Tools** - importing a statement and the calculator: doing something;
///   * **App** - settings, backup, help and about: the app itself.
///
/// The account is at the top, logging out at the bottom, apart from the
/// rest. Each group is one card of rows rather than a card per item, so the
/// page reads as three things instead of eleven.
///
/// Every row opens a named route, so what each one leads to is defined in one
/// place (`RoutePaths` and `_generateRoute`) and can be checked.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

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
    final glass = context.glass;
    void open(String route) => Navigator.of(context).pushNamed(route);

    // Only what the row needs, so the page is not rebuilt by unrelated
    // changes in either provider.
    final updateVersion = context.select<UpdateProvider, String?>(
      (updates) => updates.isUpdateAvailable ? updates.latestVersion : null,
    );

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: <Widget>[
          Text(context.t('More', 'थप'), style: theme.textTheme.headlineMedium),
          const SizedBox(height: 16),
          const _AccountCard(),
          const SizedBox(height: 22),
          _Group(
            label: context.t('Plan & track', 'योजना र हिसाब'),
            rows: <_Row>[
              _Row(
                key: const ValueKey<String>('more-budgets'),
                icon: Icons.account_balance_wallet_rounded,
                color: const Color(0xFF30D158),
                title: context.t('Budgets', 'बजेटहरू'),
                subtitle: context.t(
                  'Monthly limits by category',
                  'श्रेणी अनुसार मासिक सीमा',
                ),
                onTap: () => open(RoutePaths.budgets),
              ),
              _Row(
                key: const ValueKey<String>('more-reports'),
                icon: Icons.bar_chart_rounded,
                color: const Color(0xFF0A84FF),
                title: context.t('Reports', 'प्रतिवेदनहरू'),
                subtitle: context.t(
                  'Charts, PDF and CSV export',
                  'चार्ट, PDF र CSV निर्यात',
                ),
                onTap: () => open(RoutePaths.reports),
              ),
              _Row(
                key: const ValueKey<String>('more-calendar'),
                icon: Icons.calendar_month_rounded,
                color: const Color(0xFFFF9F0A),
                title: context.t('Calendar', 'पात्रो'),
                subtitle: context.t(
                  'Dates, tithi and festivals',
                  'मिति, तिथि र चाडपर्व',
                ),
                onTap: () => open(RoutePaths.festivals),
              ),
            ],
          ),
          _Group(
            label: context.t('Tools', 'औजारहरू'),
            rows: <_Row>[
              _Row(
                key: const ValueKey<String>('more-import'),
                icon: Icons.receipt_long_rounded,
                color: const Color(0xFF64D2FF),
                title: context.t('Import statement', 'स्टेटमेन्ट आयात'),
                subtitle: context.t(
                  'Bank, eSewa and Khalti files',
                  'बैंक, eSewa र Khalti का फाइल',
                ),
                onTap: () => open(RoutePaths.statementImport),
              ),
              _Row(
                key: const ValueKey<String>('more-calculator'),
                icon: Icons.calculate_rounded,
                color: const Color(0xFFBF5AF2),
                title: context.t('Calculator', 'क्याल्कुलेटर'),
                subtitle: context.t('Quick calculations', 'द्रुत हिसाबकिताब'),
                onTap: () => open(RoutePaths.calculator),
              ),
            ],
          ),
          _Group(
            label: context.t('App', 'एप'),
            rows: <_Row>[
              _Row(
                key: const ValueKey<String>('more-settings'),
                icon: Icons.settings_rounded,
                color: const Color(0xFF8E8E93),
                title: context.t('Settings', 'सेटिङहरू'),
                subtitle: context.t(
                  'Theme, language, notifications, security',
                  'थिम, भाषा, सूचना, सुरक्षा',
                ),
                onTap: () => open(RoutePaths.settings),
              ),
              _Row(
                key: const ValueKey<String>('more-backup'),
                icon: Icons.cloud_sync_rounded,
                color: const Color(0xFF5E5CE6),
                title: context.t('Backup & restore', 'ब्याकअप र रिस्टोर'),
                subtitle: context.t(
                  'Cloud, Google Drive or a file',
                  'क्लाउड, Google Drive वा फाइल',
                ),
                onTap: () => open(RoutePaths.backup),
              ),
              _Row(
                key: const ValueKey<String>('more-help'),
                icon: Icons.help_outline_rounded,
                color: const Color(0xFF32ADE6),
                title: context.t('Help & Support', 'मद्दत र सहयोग'),
                subtitle: context.t('Guides and answers', 'मार्गदर्शन र उत्तर'),
                onTap: () => open(RoutePaths.help),
              ),
              _Row(
                key: const ValueKey<String>('more-about'),
                icon: Icons.info_outline_rounded,
                color: const Color(0xFFFF375F),
                title: context.t('About Kharcha', 'खर्चा बारे'),
                subtitle: updateVersion == null
                    ? context.t(
                        'Version ${AppInfo.version}',
                        'संस्करण ${AppInfo.version}',
                      )
                    : context.t(
                        'Version ${AppInfo.version} · $updateVersion is out',
                        'संस्करण ${AppInfo.version} · $updateVersion उपलब्ध',
                      ),
                badge: updateVersion == null
                    ? null
                    : context.t('Update', 'अपडेट'),
                onTap: () => open(RoutePaths.about),
              ),
            ],
          ),
          GlassCard(
            key: const ValueKey<String>('more-logout'),
            onTap: () => _logout(context),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Icon(Icons.logout_rounded, color: glass.danger, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    context.t('Log out', 'लग आउट'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: glass.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Who is signed in, leading to their profile and settings. A guest is told
/// so, with the way to keep their data.
class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final name = context.select<AuthProvider, String?>((a) => a.profileName);
    final email = context.select<AuthProvider, String?>((a) => a.userEmail);
    final guest = context.select<AuthProvider, bool>((a) => a.isGuest);

    final title = guest
        ? context.t('Guest', 'पाहुना')
        : (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (email ?? context.t('Your account', 'तपाईंको खाता'));
    final subtitle = guest
        ? context.t(
            'Your data is only on this phone until you create an account.',
            'खाता नबनाउँदासम्म तपाईंको डाटा यही फोनमा मात्र छ।',
          )
        : (name != null && name.trim().isNotEmpty ? (email ?? '') : '');
    final letter = title.trim().isEmpty ? '?' : title.trim()[0].toUpperCase();

    return GlassCard(
      key: const ValueKey<String>('more-account'),
      onTap: () => Navigator.of(context).pushNamed(RoutePaths.settings),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.16),
                ),
                child: Text(
                  letter,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: glass.textSecondary,
                        ),
                        maxLines: guest ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: glass.textTertiary),
            ],
          ),
          if (guest) ...<Widget>[
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              key: const ValueKey<String>('more-save-data'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const GuestUpgradeScreen(),
                ),
              ),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: Text(
                context.t('Save your data', 'डाटा सुरक्षित गर्नुहोस्'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A labelled group: one card holding its rows, separated by hairlines.
class _Group extends StatelessWidget {
  const _Group({required this.label, required this.rows});

  final String label;
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: glass.textTertiary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < rows.length; i++) ...<Widget>[
                    if (i != 0)
                      Divider(
                        height: 1,
                        indent: 68,
                        color: glass.textTertiary.withValues(alpha: 0.18),
                      ),
                    rows[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// A short word shown before the chevron, e.g. `Update`.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
                  Text(
                    title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: glass.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (badge != null) ...<Widget>[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: glass.textTertiary),
          ],
        ),
      ),
    );
  }
}
