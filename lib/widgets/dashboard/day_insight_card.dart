import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ai_insight_model.dart';
import '../../models/app_settings_model.dart';
import '../../models/financial_summary.dart';
import '../../providers/ai_insight_provider.dart';
import '../../providers/festival_provider.dart';
import '../../screens/ai/ai_chat_sheet.dart';
import '../../services/nepali_date_service.dart';
import '../common/festival_image.dart';
import '../common/flame_mascot.dart';
import '../common/glass_card.dart';

/// One compact dashboard card that combines:
///  * the Bikram Sambat day (day number + month),
///  * the next festival / public holiday with its days-remaining countdown,
///  * the AI insight (with a manual refresh and an "Ask AI" entry point).
///
/// Replaces the separate calendar, festival and AI cards so the home dashboard
/// stays short. Tapping the card opens the full calendar.
class DayInsightCard extends StatelessWidget {
  const DayInsightCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final dates = context.read<NepaliDateService>();
    final festivals = context.watch<FestivalProvider>();
    final ai = context.watch<AiInsightProvider>();

    final today = dates.today();
    final holiday = festivals.nextPublicHoliday();
    final insight = ai.insight;
    final mood = ai.mood;
    final bool useAd = dates.calendarSystem == CalendarSystem.ad;
    final DateTime gregorianNow = DateTime.now();

    return GlassCard(
      onTap: () => Navigator.of(context).pushNamed(RoutePaths.festivals),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          theme.colorScheme.primary.withValues(alpha: 0.16),
          Colors.transparent,
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _DayBadge(
                day: useAd ? gregorianNow.day : today.day,
                month: useAd
                    ? dates.gregorianMonthName(gregorianNow.month)
                    : dates.monthName(today.month),
                imagePath: holiday?.imagePath,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      holiday?.name ??
                          context.t('No upcoming festival', 'आगामी चाड छैन'),
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      holiday == null
                          ? dates.formatBs(today, style: BsFormat.full)
                          : dates.formatBs(
                              BsDate(
                                holiday.bsYear,
                                holiday.bsMonth,
                                holiday.bsDay,
                              ),
                              style: BsFormat.long,
                            ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: glass.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (holiday != null) ...<Widget>[
                      const SizedBox(height: 8),
                      _CountdownPill(
                        days: holiday.daysRemaining(DateTime.now()),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: glass.textTertiary),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: glass.textTertiary.withValues(alpha: 0.18)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              FlameMascot(
                face: mood?.face ?? MoodFace.calm,
                tone: mood?.tone ?? MoodTone.neutral,
                energy: mood?.energy,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InsightText(
                  insight: insight,
                  mood: mood,
                  loading: ai.isLoading,
                  onActionTap: (action) =>
                      _openChat(context, initialPrompt: action),
                ),
              ),
              _RefreshButton(loading: ai.isLoading, onTap: ai.regenerate),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              TextButton.icon(
                onPressed: () => _openChat(context),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                label: Text(context.t('Ask AI', 'AI लाई सोध्नुहोस्')),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (mood != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: mood.color(context).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(mood.emoji, style: const TextStyle(fontSize: 11)),
                      const SizedBox(width: 4),
                      Text(
                        mood.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: mood.color(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _openChat(BuildContext context, {String? initialPrompt}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiChatSheet(initialQuestion: initialPrompt),
    );
  }
}

/// Today's day and month, the first thing read on the card.
///
/// When a festival is coming up its photograph sits behind the date as a soft,
/// blurred wash: enough to hint at the festival, never enough to compete with
/// the numbers. Without one the badge is a plain tint.
class _DayBadge extends StatelessWidget {
  const _DayBadge({required this.day, required this.month, this.imagePath});

  final int day;
  final String month;
  final String? imagePath;

  static const double _size = 58;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final image = imagePath;
    final tint = ColoredBox(color: scheme.primary.withValues(alpha: 0.16));

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (image == null)
              tint
            else ...<Widget>[
              // Decoration only, so it is hidden from screen readers.
              ExcludeSemantics(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: 5,
                    sigmaY: 5,
                    tileMode: TileMode.clamp,
                  ),
                  child: FestivalImage(
                    assetPath: image,
                    width: _size,
                    height: _size,
                    fallback: tint,
                  ),
                ),
              ),
              // The theme's own surface laid over the photo keeps the date
              // readable on any picture, in light and dark alike.
              ColoredBox(color: scheme.surface.withValues(alpha: 0.72)),
              tint,
            ],
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  '$day',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      month,
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CountdownPill extends StatelessWidget {
  const _CountdownPill({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (days) {
      < 0 => context.t('Passed', 'बितिसक्यो'),
      0 => context.t('Today', 'आज'),
      1 => context.t('Tomorrow', 'भोलि'),
      _ => context.t('In $days days', '${L10n.neNumber(days)} दिनमा'),
    };
    final soon = days >= 0 && days <= 3;
    final color = soon
        ? theme.colorScheme.primary
        : context.glass.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.event_rounded, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightText extends StatelessWidget {
  const _InsightText({
    required this.insight,
    required this.loading,
    this.mood,
    this.onActionTap,
  });

  final AiInsight? insight;
  final bool loading;
  final AiMood? mood;
  final ValueChanged<String>? onActionTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;

    if (insight == null) {
      if (loading) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.t('Generating your insight…', 'तपाईंको सुझाव बन्दैछ…'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: glass.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            if (mood != null)
              Text(
                mood!.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: mood!.color(context).withValues(alpha: 0.8),
                  height: 1.3,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.t(
              'Tap refresh to generate your first insight.',
              'पहिलो सुझावका लागि refresh थिच्नुहोस्।',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: glass.textSecondary,
            ),
          ),
          if (mood != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              mood!.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: glass.textSecondary,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          insight!.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          insight!.message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: glass.textSecondary,
            height: 1.35,
          ),
        ),
        if (insight!.action.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onActionTap == null
                ? null
                : () => onActionTap!(insight!.action.trim()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                insight!.action.trim(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _RefreshButton extends StatefulWidget {
  const _RefreshButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.loading) _controller.repeat();
  }

  @override
  void didUpdateWidget(_RefreshButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.loading && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: widget.loading ? null : widget.onTap,
      tooltip: 'Regenerate',
      visualDensity: VisualDensity.compact,
      icon: RotationTransition(
        turns: _controller,
        child: Icon(
          Icons.refresh_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
