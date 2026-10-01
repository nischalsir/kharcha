import 'package:flutter/material.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../screens/budgets/budgets_screen.dart';
import '../../screens/calculator/calculator_screen.dart';
import '../../screens/festivals/festivals_screen.dart';
import '../../screens/reports/reports_screen.dart';
import '../../screens/settings/settings_screen.dart';

class RootDrawer extends StatelessWidget {
  const RootDrawer({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.friendOverdue,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final int friendOverdue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final primary = theme.colorScheme.primary;

    Widget tile({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool active = false,
      int badgeCount = 0,
    }) {
      return ListTile(
        leading: Badge(
          isLabelVisible: badgeCount > 0,
          label: badgeCount > 0 ? Text('$badgeCount') : null,
          child: Icon(icon, color: active ? primary : glass.textSecondary),
        ),
        title: Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            color: active ? primary : glass.textTertiary,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        selected: active,
        selectedTileColor: primary.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: onTap,
      );
    }

    Widget sectionLabel(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: glass.textSecondary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );

    void goToTab(int index) {
      Navigator.of(context).pop();
      onTabSelected(index);
    }

    void openTool(WidgetBuilder builder) {
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
    }

    return Drawer(
      backgroundColor: glass.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      color: primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Kharcha',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            sectionLabel(context.t('Main', 'मुख्य')),
            tile(
              icon: Icons.home_outlined,
              label: context.t('Home', 'गृह'),
              active: currentIndex == 0,
              onTap: () => goToTab(0),
            ),
            tile(
              icon: Icons.receipt_long_outlined,
              label: context.t('Payments', 'भुक्तानी'),
              active: currentIndex == 1,
              onTap: () => goToTab(1),
            ),
            tile(
              icon: Icons.people_outline,
              label: context.t('Friends', 'साथीहरू'),
              active: currentIndex == 2,
              badgeCount: friendOverdue,
              onTap: () => goToTab(2),
            ),
            tile(
              icon: Icons.storefront_outlined,
              label: context.t('Pasal', 'पसल'),
              active: currentIndex == 3,
              onTap: () => goToTab(3),
            ),
            tile(
              icon: Icons.more_horiz,
              label: context.t('More', 'थप'),
              active: currentIndex == 4,
              onTap: () => goToTab(4),
            ),
            sectionLabel(context.t('Tools', 'उपकरणहरू')),
            tile(
              icon: Icons.calculate_rounded,
              label: context.t('Calculator', 'क्याल्कुलेटर'),
              onTap: () => openTool((_) => const CalculatorScreen()),
            ),
            tile(
              icon: Icons.account_balance_wallet_rounded,
              label: context.t('Budgets', 'बजेटहरू'),
              onTap: () => openTool((_) => const BudgetsScreen()),
            ),
            tile(
              icon: Icons.calendar_month_rounded,
              label: context.t('Calendar', 'पात्रो'),
              onTap: () => openTool((_) => const FestivalsScreen()),
            ),
            tile(
              icon: Icons.bar_chart_rounded,
              label: context.t('Reports', 'प्रतिवेदनहरू'),
              onTap: () => openTool((_) => const ReportsScreen()),
            ),
            tile(
              icon: Icons.settings_rounded,
              label: context.t('Settings', 'सेटिङहरू'),
              onTap: () => openTool((_) => const SettingsScreen()),
            ),
          ],
        ),
      ),
    );
  }
}
