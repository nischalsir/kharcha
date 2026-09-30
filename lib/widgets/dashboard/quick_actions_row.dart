import 'package:flutter/material.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../screens/friends/friends_screen.dart';
import '../../screens/payments/payments_screen.dart';
import '../common/pressable_scale.dart';

class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = <_QuickAction>[
      _QuickAction(context.t('Add Expense', 'खर्च थप्नुहोस्'), Icons.remove_circle_outline, () {
        Navigator.of(context).pushNamed(RoutePaths.addExpense);
      }),
      _QuickAction(context.t('Add Income', 'आम्दानी थप्नुहोस्'), Icons.add_circle_outline, () {
        Navigator.of(context).pushNamed(RoutePaths.addIncome);
      }),
      _QuickAction(context.t('Add Payment', 'भुक्तानी थप्नुहोस्'), Icons.payments_outlined, () {
        showAddRecurringPaymentSheet(context);
      }),
      _QuickAction(context.t('Friend Credit', 'साथीको कर्जा'), Icons.people_outline, () {
        showAddFriendSheet(context);
      }),
      _QuickAction(context.t('Calculator', 'क्याल्कुलेटर'), Icons.calculate_outlined, () {
        Navigator.of(context).pushNamed(RoutePaths.calculator);
      }),
    ];
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) => actions[index],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(this.label, this.icon, this.onTap);

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return PressableScale(
      onTap: onTap,
      child: SizedBox(
        width: 76,
        child: Column(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: glass.surfaceStrong,
                  border: Border.all(color: glass.border, width: 0.8),
                ),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(icon, color: theme.colorScheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
