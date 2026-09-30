import 'package:flutter/material.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../providers/dashboard_provider.dart';
import '../common/glass_card.dart';

/// Compact "spending this month" card.
///
/// Only the essentials: how much went out, how that compares to what came in,
/// one segmented bar for where it went, and the top three categories as a
/// tight legend. Everything else lives on the Reports screen.
class SpendingChartCard extends StatelessWidget {
  const SpendingChartCard({
    super.key,
    required this.categorySpend,
    this.categoryNames = const <String, String>{},
    this.monthIncome = 0,
  });

  final List<CategorySpend> categorySpend;

  /// Category id to display name.
  final Map<String, String> categoryNames;

  /// Income recorded this month, used for the "of income" line.
  final double monthIncome;

  static const List<Color> _palette = <Color>[
    Color(0xFF0A84FF),
    Color(0xFFBF5AF2),
    Color(0xFFFF9F0A),
  ];

  String _labelFor(BuildContext context, String? id) {
    if (id == null || id.isEmpty) {
      return context.t('Uncategorized', 'श्रेणीविहीन');
    }
    final name = categoryNames[id]?.trim() ?? '';
    return name.isEmpty ? context.t('Uncategorized', 'श्रेणीविहीन') : name;
  }

  /// "42% of income", capped at "999%+" so a tiny income cannot produce a
  /// fourteen-digit percentage.
  static String _shareLabel(BuildContext context, double share) {
    final pct = (share * 100).round();
    if (pct > 999) {
      return context.t('999%+ of income', 'आम्दानीको ${L10n.neNumber(999)}%+');
    }
    return context.t('$pct% of income', 'आम्दानीको ${L10n.neNumber(pct)}%');
  }

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final theme = Theme.of(context);

    final total = categorySpend.fold<double>(0, (sum, e) => sum + e.amount);
    final top = categorySpend.take(3).toList();
    final restAmount = total - top.fold<double>(0, (s, e) => s + e.amount);

    // Share of this month's income already spent: the single number that
    // says whether the month is going well.
    final incomeShare = monthIncome > 0 ? total / monthIncome : null;
    final shareColor = incomeShare == null
        ? glass.textSecondary
        : incomeShare >= 1
        ? glass.danger
        : incomeShare >= 0.8
        ? glass.warning
        : glass.success;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.t('Spent this month', 'यस महिनाको खर्च'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: glass.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    CurrencyFormatter.format(total),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (incomeShare != null) ...<Widget>[
                const SizedBox(width: 8),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      _shareLabel(context, incomeShare),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: shareColor,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (total <= 0) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              context.t('No expenses yet this month', 'यस महिना खर्च छैन'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: glass.textSecondary,
              ),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 14),
            _SegmentedBar(
              segments: <({double value, Color color})>[
                for (var i = 0; i < top.length; i++)
                  (value: top[i].amount, color: _palette[i]),
                if (restAmount > 0)
                  (value: restAmount, color: glass.textTertiary),
              ],
              total: total,
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < top.length; i++)
              _LegendRow(
                color: _palette[i],
                label: _labelFor(context, top[i].categoryId),
                amount: top[i].amount,
              ),
          ],
        ],
      ),
    );
  }
}

class _SegmentedBar extends StatelessWidget {
  const _SegmentedBar({required this.segments, required this.total});

  final List<({double value, Color color})> segments;
  final double total;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 8,
        child: Row(
          children: <Widget>[
            for (var i = 0; i < segments.length; i++) ...<Widget>[
              Expanded(
                // Flex needs ints; per-mille keeps small slices visible.
                flex: ((segments[i].value / total) * 1000).round().clamp(
                  1,
                  1000,
                ),
                child: ColoredBox(color: segments[i].color),
              ),
              if (i < segments.length - 1) const SizedBox(width: 2),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.amount,
  });

  final Color color;
  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            CurrencyFormatter.compact(amount),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
