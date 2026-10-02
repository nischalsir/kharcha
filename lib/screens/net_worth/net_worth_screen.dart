import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/net_worth.dart';
import '../../models/sync_models.dart';
import '../../models/transaction_model.dart';
import '../../providers/friend_provider.dart';
import '../../providers/loan_provider.dart';
import '../../providers/pasal_provider.dart';
import '../../providers/savings_goal_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../repositories/cached_repository.dart';
import '../../services/cache_service.dart';
import '../../services/nepali_date_service.dart';
import '../../widgets/common/glass_back_button.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/page_refresh.dart';

/// What you have, what you owe, and what is left: the wallets, what friends
/// owe you, what you owe them and the shops, and the loans, in one figure
/// with how it has moved over the last six months.
class NetWorthScreen extends StatelessWidget {
  const NetWorthScreen({super.key, this.now});

  /// "Today", fixed in tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final dates = context.read<NepaliDateService>();

    final wallets = context.watch<WalletProvider>();
    final friends = context.watch<FriendProvider>().summary();
    final pasal = context.watch<PasalProvider>().overallSummary();
    final loans = context.watch<LoanProvider>();
    final goals = context.watch<SavingsGoalProvider>();

    final worth = NetWorth(
      wallets: wallets.total,
      owedToYou: friends.othersOweYou,
      youOweFriends: friends.youOwe,
      pasalDues: pasal.totalOutstanding,
      loans: loans.totalOutstanding,
    );
    final today = now ?? DateTime.now();
    final trend = NetWorthTrend.build(
      current: worth.total,
      transactions: readTyped<TransactionModel>(
        context.read<CacheService>(),
        SyncEntity.transactions,
        TransactionModel.fromJson,
      ),
      now: today,
    );
    final change = trend.length < 2
        ? 0.0
        : trend.last.value - trend[trend.length - 2].value;
    final positive = worth.total >= 0;

    Widget line({
      required Key key,
      required IconData icon,
      required Color color,
      required String label,
      required double amount,
      required String route,
      bool owed = false,
    }) => ListTile(
      key: key,
      dense: true,
      onTap: () => Navigator.of(context).pushNamed(route),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        '${owed && amount > 0 ? '− ' : ''}'
        '${CurrencyFormatter.format(amount)}',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: owed && amount > 0 ? glass.danger : null,
        ),
      ),
    );

    Widget group(String title, double total, List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: glass.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                CurrencyFormatter.format(total),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: glass.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: <Widget>[
                for (var i = 0; i < rows.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1, indent: 60),
                  rows[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Navigator.of(context).canPop()
              ? const GlassBackButton()
              : null,
          title: Text(
            context.t('Net worth', 'कुल सम्पत्ति'),
            style: theme.textTheme.titleLarge,
          ),
        ),
        body: SafeArea(
          child: PageRefresh(
            pageName: 'Net worth',
            pageNameNe: 'कुल सम्पत्ति',
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
              children: <Widget>[
                GlassCard(
                  radius: 28,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      (positive ? glass.success : glass.danger).withValues(
                        alpha: 0.16,
                      ),
                      Colors.transparent,
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.t(
                          'What you have, less what you owe',
                          'तपाईंसँग भएको, तिर्नुपर्ने घटाएर',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: glass.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          CurrencyFormatter.format(worth.total),
                          key: const ValueKey<String>('net-worth-total'),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: positive ? null : glass.danger,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        change == 0
                            ? context.t(
                                'No change this month',
                                'यो महिना परिवर्तन छैन',
                              )
                            : context.t(
                                '${change > 0 ? 'Up' : 'Down'} '
                                    '${CurrencyFormatter.format(change.abs())} '
                                    'this month',
                                'यो महिना '
                                    '${CurrencyFormatter.format(change.abs())} '
                                    '${change > 0 ? 'बढ्यो' : 'घट्यो'}',
                              ),
                        key: const ValueKey<String>('net-worth-change'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: change == 0
                              ? glass.textSecondary
                              : change > 0
                              ? glass.success
                              : glass.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 96,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _TrendPainter(
                            values: <double>[for (final p in trend) p.value],
                            line: positive ? glass.success : glass.danger,
                            grid: glass.textTertiary.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          for (final point in trend)
                            Text(
                              dates.gregorianMonthName(
                                point.month.month,
                                short: true,
                              ),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: glass.textTertiary,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                group(
                  context.t('What you have', 'तपाईंसँग भएको'),
                  worth.assets,
                  <Widget>[
                    line(
                      key: const ValueKey<String>('net-worth-wallets'),
                      icon: Icons.account_balance_wallet_rounded,
                      color: const Color(0xFF30D158),
                      label: context.t('Wallets', 'वालेट'),
                      amount: worth.wallets,
                      route: RoutePaths.wallets,
                    ),
                    line(
                      key: const ValueKey<String>('net-worth-receivable'),
                      icon: Icons.call_received_rounded,
                      color: const Color(0xFFBF5AF2),
                      label: context.t('Friends owe you', 'साथीले तिर्नुपर्ने'),
                      amount: worth.owedToYou,
                      route: RoutePaths.friends,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                group(
                  context.t('What you owe', 'तपाईंले तिर्नुपर्ने'),
                  worth.liabilities,
                  <Widget>[
                    line(
                      key: const ValueKey<String>('net-worth-loans'),
                      icon: Icons.account_balance_rounded,
                      color: const Color(0xFFFF9F0A),
                      label: context.t('Loans', 'ऋण'),
                      amount: worth.loans,
                      route: RoutePaths.loans,
                      owed: true,
                    ),
                    line(
                      key: const ValueKey<String>('net-worth-pasal'),
                      icon: Icons.storefront_rounded,
                      color: const Color(0xFF64D2FF),
                      label: context.t('Shop tabs', 'पसलको उधारो'),
                      amount: worth.pasalDues,
                      route: RoutePaths.pasal,
                      owed: true,
                    ),
                    line(
                      key: const ValueKey<String>('net-worth-payable'),
                      icon: Icons.call_made_rounded,
                      color: const Color(0xFFFF453A),
                      label: context.t(
                        'You owe friends',
                        'साथीलाई तिर्नुपर्ने',
                      ),
                      amount: worth.youOweFriends,
                      route: RoutePaths.friends,
                      owed: true,
                    ),
                  ],
                ),
                if (goals.totalSaved > 0) ...<Widget>[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      context.t(
                        '${CurrencyFormatter.format(goals.totalSaved)} of '
                            'this is set aside for your savings goals.',
                        'यसमध्ये ${CurrencyFormatter.format(goals.totalSaved)} '
                            'बचत लक्ष्यका लागि छुट्याइएको छ।',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: glass.textSecondary,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    context.t(
                      'The line is worked back from today using what you '
                          'earned and spent each month.',
                      'रेखा आजबाट पछाडि, हरेक महिनाको आम्दानी र खर्चका '
                          'आधारमा निकालिएको हो।',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: glass.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The trend as a line with a soft fill under it and a dot on today.
class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.values,
    required this.line,
    required this.grid,
  });

  final List<double> values;
  final Color line;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final span = (high - low).abs() < 0.01 ? 1.0 : high - low;
    const inset = 6.0;
    final usable = size.height - inset * 2;

    Offset at(int index) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * index / (values.length - 1);
      final y = high == low
          ? size.height / 2
          : inset + usable * (1 - (values[index] - low) / span);
      return Offset(x, y);
    }

    // Where zero is, when the line crosses it.
    if (low < 0 && high > 0) {
      final zero = inset + usable * (1 - (0 - low) / span);
      canvas.drawLine(
        Offset(0, zero),
        Offset(size.width, zero),
        Paint()
          ..color = grid
          ..strokeWidth = 1,
      );
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            line.withValues(alpha: 0.28),
            line.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(at(values.length - 1), 4.5, Paint()..color = line);
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.line != line || old.grid != grid || !_same(old.values, values);

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
