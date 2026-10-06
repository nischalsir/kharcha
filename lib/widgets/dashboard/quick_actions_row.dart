import 'package:flutter/material.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/router/route_paths.dart';
import '../../screens/friends/friends_screen.dart';
import '../../screens/payments/payments_screen.dart';
import '../common/pressable_scale.dart';

/// The row of shortcuts under the budget on Home.
///
/// All of them are on screen at once, sharing the width evenly: nothing has
/// to be found by scrolling sideways, and on a narrow phone the tiles get
/// smaller instead of the last one being cut off.
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = <_QuickAction>[
      _QuickAction(
        const ValueKey<String>('quick-add-expense'),
        context.t('Add Expense', 'खर्च थप्नुहोस्'),
        Icons.remove_circle_outline,
        () => Navigator.of(context).pushNamed(RoutePaths.addExpense),
      ),
      _QuickAction(
        const ValueKey<String>('quick-add-income'),
        context.t('Add Income', 'आम्दानी थप्नुहोस्'),
        Icons.add_circle_outline,
        () => Navigator.of(context).pushNamed(RoutePaths.addIncome),
      ),
      // A bill that comes back (rent, internet), not a one-off payment:
      // named for that, so it is not taken for a second "Add Expense".
      _QuickAction(
        const ValueKey<String>('quick-add-payment'),
        context.t('Recurring Bill', 'दोहोरिने बिल'),
        Icons.event_repeat_rounded,
        () => showAddRecurringPaymentSheet(context),
      ),
      _QuickAction(
        const ValueKey<String>('quick-friend-credit'),
        context.t('Friend Credit', 'साथीको कर्जा'),
        Icons.people_outline,
        () => showAddFriendSheet(context),
      ),
      _QuickAction(
        const ValueKey<String>('quick-calculator'),
        context.t('Calculator', 'क्याल्कुलेटर'),
        Icons.calculate_outlined,
        () => Navigator.of(context).pushNamed(RoutePaths.calculator),
      ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[for (final action in actions) Expanded(child: action)],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(Key key, this.label, this.icon, this.onTap)
    : super(key: key);

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PressableScale(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The same flat fill as the cards around it, and like them no
          // outline: the grey on the white page is its edge.
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: scheme.primary),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              label,
              style: theme.textTheme.labelSmall,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
