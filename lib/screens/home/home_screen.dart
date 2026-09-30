import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../providers/ai_insight_provider.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../widgets/common/ai_mood_badge.dart';
import '../../widgets/common/animated_number.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/common/stat_card.dart';
import '../../widgets/dashboard/ai_birthday_banner.dart';
import '../../widgets/dashboard/day_insight_card.dart';
import '../../widgets/dashboard/pasal_summary_card.dart';
import '../../widgets/dashboard/quick_actions_row.dart';
import '../../widgets/dashboard/recent_payments_list.dart';
import '../../widgets/dashboard/spending_chart_card.dart';
import '../../widgets/dashboard/timed_greeting.dart';
import '../../widgets/dashboard/upcoming_recurring_list.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _avatarUrl;
  String? _avatarLoadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    final birthDate = auth.profileBirthDate;
    final now = DateTime.now();
    context.read<AiInsightProvider>()
      ..updateUser(
        name: auth.profileName,
        isBirthday:
            birthDate != null &&
            birthDate.month == now.month &&
            birthDate.day == now.day,
      )
      ..ensureLoaded();
    _loadAvatar();
  }

  /// Resolves the avatar once per signed-in user and caches it in state, so a
  /// rebuild never re-runs the network lookup and resets the picture to the
  /// fallback (the bug a `FutureBuilder` in `build` caused).
  void _loadAvatar() {
    final auth = context.read<AuthProvider>();
    final uid = auth.userId;
    if (uid == null || uid == _avatarLoadedFor) return;
    _avatarLoadedFor = uid;
    _avatarUrl = null;
    auth.signedAvatarUrl().then((url) {
      if (mounted && uid == context.read<AuthProvider>().userId) {
        setState(() => _avatarUrl = url);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardProvider>();
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final glass = context.glass;
    final data = dashboard.data;

    final userName = auth.profileName;
    // The spending legend needs names, not the category row ids the dashboard
    // aggregates by.
    final categoryNames = <String, String>{
      for (final category in context.watch<AppSettingsProvider>().categories)
        category.id: category.name,
    };

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        TimedGreeting(
                          style: theme.textTheme.headlineMedium,
                        ),
                        if (userName != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            userName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      _HeaderAvatar(url: _avatarUrl, name: userName),
                      const SizedBox(height: 6),
                      Text(
                        dashboard.todayLabel(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: glass.textSecondary,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(child: const AiBirthdayBanner()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: GlassCard(
                strong: true,
                glow: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            context.t('Total Balance', 'कुल बचत'),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: glass.textSecondary,
                            ),
                          ),
                        ),
                        AiMoodBadge(
                          mood: context.watch<AiInsightProvider>().mood,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    AnimatedNumber(
                      value: data.totalBalance,
                      style: theme.textTheme.displaySmall,
                    ),
                    const _MoodReactionBubble(),
                    const SizedBox(height: 18),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _MiniStat(
                            label: context.t('Income', 'आम्दानी'),
                            value: data.totalIncome,
                            color: glass.success,
                            icon: Icons.south_west,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MiniStat(
                            label: context.t('Expenses', 'खर्च'),
                            value: data.totalExpense,
                            color: glass.danger,
                            icon: Icons.north_east,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MiniStat(
                            label: context.t('Savings', 'बचत'),
                            value: data.netSavings,
                            color: theme.colorScheme.primary,
                            icon: Icons.savings_outlined,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (data.monthlyBudget > 0)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(child: _BudgetSummaryCard(data: data)),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(child: const QuickActionsRow()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(child: const DayInsightCard()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: SpendingChartCard(
                categorySpend: data.categorySpend,
                categoryNames: categoryNames,
                monthIncome: data.totalIncome,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            sliver: SliverToBoxAdapter(
              child: SectionHeader(
                title: context.t('Recent Payments', 'हालैका भुक्तानीहरू'),
                actionLabel: context.t('See all', 'सबै हेर्नुहोस्'),
                onAction: () =>
                    Navigator.of(context).pushNamed(RoutePaths.payments),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            sliver: SliverToBoxAdapter(
              child: RecentPaymentsList(items: data.recentTransactions),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(child: const _FriendsSummaryCard()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(child: const PasalSummaryCard()),
          ),
          if (data.upcomingRecurring.isNotEmpty) ...<Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(
                  title: context.t(
                    'Upcoming Recurring Payments',
                    'आगामी आवर्ती भुक्तानीहरू',
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              sliver: SliverToBoxAdapter(
                child: UpcomingRecurringList(items: data.upcomingRecurring),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({this.url, this.name});

  final String? url;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final trimmed = name?.trim();
    final initial = (trimmed != null && trimmed.isNotEmpty)
        ? trimmed[0].toUpperCase()
        : null;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.35),
          width: 2,
        ),
        gradient: url == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[colorScheme.primary, colorScheme.secondary],
              )
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(theme, initial),
            )
          : _fallback(theme, initial),
    );
  }

  Widget _fallback(ThemeData theme, String? initial) {
    return Center(
      child: initial != null
          ? Text(
              initial,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            )
          : const Icon(Icons.person_rounded, color: Colors.white, size: 24),
    );
  }
}

/// A short-lived speech bubble under the balance, shown only while the mascot
/// is reacting to a transaction the user just added.
///
/// Reads `reaction` rather than `mood` on purpose: the standing time/weather
/// mood is always present and would keep this bubble on screen permanently.
class _MoodReactionBubble extends StatelessWidget {
  const _MoodReactionBubble();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reaction = context.watch<AiInsightProvider>().reaction;

    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: reaction == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: reaction.color(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: reaction.color(context).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(reaction.emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        reaction.message,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: reaction.color(context),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final double value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: glass.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            CurrencyFormatter.compact(value),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _BudgetSummaryCard extends StatelessWidget {
  const _BudgetSummaryCard({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final fraction = data.budgetFraction.clamp(0, 1).toDouble();
    final over = data.budgetFraction >= 1;
    final color = over
        ? glass.danger
        : data.budgetFraction >= 0.8
        ? glass.warning
        : glass.success;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.t('Monthly Budget', 'मासिक बजेट'),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                context.t(
                  '${(fraction * 100).round()}% Used',
                  '${L10n.neNumber((fraction * 100).round())}% प्रयोग',
                ),
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: fraction),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 10,
                backgroundColor: glass.surface,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '${CurrencyFormatter.format(data.budgetSpent)} / '
                '${CurrencyFormatter.format(data.monthlyBudget)}',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                '${context.t('Remaining', 'बाँकी')} ${CurrencyFormatter.format(data.budgetRemaining)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: glass.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FriendsSummaryCard extends StatelessWidget {
  const _FriendsSummaryCard();

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardProvider>().data;
    return Row(
      children: <Widget>[
        Expanded(
          child: StatCard(
            label: context.t('You Owe', 'तिर्नुपर्ने'),
            value: dashboard.friendYouOwe,
            icon: Icons.arrow_upward,
            color: context.glass.danger,
            onTap: () => Navigator.of(context).pushNamed(RoutePaths.friends),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            label: context.t('Owed To You', 'पाउनुपर्ने'),
            value: dashboard.friendTheyOwe,
            icon: Icons.arrow_downward,
            color: context.glass.success,
            onTap: () => Navigator.of(context).pushNamed(RoutePaths.friends),
          ),
        ),
      ],
    );
  }
}
