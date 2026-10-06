import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/festival_model.dart';
import '../../providers/festival_provider.dart';
import '../../services/nepali_date_service.dart';
import '../../services/tithi_service.dart';
import '../common/festival_image.dart';
import '../common/glass_card.dart';

/// Everything the app knows about one Bikram Sambat day.
///
/// The card is driven entirely by the selected [date], so tapping any cell in
/// the month grid re-renders it for that day. When no entry exists for the day
/// it still shows the date itself rather than disappearing, so the grid never
/// looks like it is missing data.
class DayInfoCard extends StatelessWidget {
  const DayInfoCard({
    super.key,
    required this.date,
    this.isToday = false,
    this.trailing,
  });

  final BsDate date;
  final bool isToday;

  /// Shown in the top-right corner of the card, e.g. today's weather.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dates = context.read<NepaliDateService>();
    final festivals = context.read<FestivalProvider>();
    final entries = festivals.forDate(date);
    final devanagari = dates.devanagari;
    final gregorian = dates.toGregorian(date);
    final weekday = dates.weekdayName(gregorian, useDevanagari: devanagari);
    final holidays = entries.where((f) => f.isPublicHoliday).toList();
    // A gazetted block such as Dashain or Tihar makes days holidays that carry
    // no entry of their own, so the block name is what the card must show.
    final blocks = festivals.holidayBlocksFor(date);
    final isHoliday = holidays.isNotEmpty || blocks.isNotEmpty;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Header(
            date: date,
            weekday: weekday,
            gregorian: gregorian,
            devanagari: devanagari,
            isToday: isToday,
            trailing: trailing,
          ),
          if (isHoliday) ...<Widget>[
            const SizedBox(height: 12),
            _HolidayStrip(
              names: holidays
                  .map((f) => f.title(devanagari: devanagari))
                  .toList(growable: false),
              blocks: blocks
                  .map((b) => devanagari ? b.nameNe : b.name)
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 14),
          if (entries.isEmpty)
            _NoEntries(
              theme: theme,
              devanagari: devanagari,
              isHolidayOnly: isHoliday,
            )
          else
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _EntryTile(entry: entry, devanagari: devanagari),
              ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.date,
    required this.weekday,
    required this.gregorian,
    required this.devanagari,
    required this.isToday,
    this.trailing,
  });

  final BsDate date;
  final String weekday;
  final DateTime gregorian;
  final bool devanagari;
  final bool isToday;
  final Widget? trailing;

  static const List<String> _gregorianMonths = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final dates = context.read<NepaliDateService>();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      dates.formatBs(date, style: BsFormat.long),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isToday) ...<Widget>[
                    const SizedBox(width: 8),
                    _Pill(
                      label: devanagari ? 'आज' : 'Today',
                      background: theme.colorScheme.primary,
                      foreground: theme.colorScheme.onPrimary,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '$weekday  •  ${gregorian.day} '
                '${_gregorianMonths[gregorian.month - 1]} ${gregorian.year}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: glass.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              _TithiLine(gregorian: gregorian, devanagari: devanagari),
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class _HolidayStrip extends StatelessWidget {
  const _HolidayStrip({required this.names, required this.blocks});

  final List<String> names;
  final List<String> blocks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final name in names)
          _Pill(
            label: name,
            background: theme.colorScheme.errorContainer,
            foreground: theme.colorScheme.onErrorContainer,
            icon: Icons.event_available_rounded,
          ),
        for (final name in blocks)
          _Pill(
            label: name,
            background: theme.colorScheme.errorContainer,
            foreground: theme.colorScheme.onErrorContainer,
            icon: Icons.beach_access_rounded,
          ),
      ],
    );
  }
}

class _NoEntries extends StatelessWidget {
  const _NoEntries({
    required this.theme,
    required this.devanagari,
    required this.isHolidayOnly,
  });

  final ThemeData theme;
  final bool devanagari;
  final bool isHolidayOnly;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    return Row(
      children: <Widget>[
        Icon(
          isHolidayOnly ? Icons.beach_access_rounded : Icons.event_busy_rounded,
          size: 18,
          color: glass.textTertiary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            isHolidayOnly
                ? (devanagari
                      ? 'यस दिन कुनै विशेष चाडपर्व छैन।'
                      : 'No named festival on this day.')
                : (devanagari
                      ? 'यस दिन कुनै चाडपर्व छैन।'
                      : 'No festival or holiday on this day.'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: glass.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.devanagari});

  final Festival entry;
  final bool devanagari;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Hero(entry: entry, devanagari: devanagari),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      entry.iconData,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        entry.title(devanagari: devanagari),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (entry.isPublicHoliday)
                      _Pill(
                        label: devanagari ? 'सार्वजनिक बिदा' : 'Public holiday',
                        background: theme.colorScheme.secondaryContainer,
                        foreground: theme.colorScheme.onSecondaryContainer,
                      ),
                  ],
                ),
                if (entry.tithi != null && entry.tithi!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.brightness_3_rounded,
                        size: 13,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        devanagari
                            ? 'तिथि: ${entry.tithi}'
                            : 'Tithi: ${entry.tithi}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
                if (entry.holidayNote != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    devanagari
                        ? 'दायरा: ${entry.holidayNote}'
                        : 'Scope: ${entry.holidayNote}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: glass.textTertiary,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  entry.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: glass.textSecondary,
                    height: 1.45,
                  ),
                ),
                if (!entry.isExactDate) ...<Widget>[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.info_outline_rounded,
                        size: 13,
                        color: glass.textTertiary,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          devanagari
                              ? 'यो ${entry.bsYear} को पञ्चाङ्गअनुसारको मिति।'
                              : 'Panchang date published for BS '
                                    '${entry.bsYear}.',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: glass.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (entry.imageCredit != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    entry.imageCredit!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: glass.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Image area for a single entry.
///
/// Shows the entry's photograph when one exists, bundled or uploaded since,
/// and a themed gradient with the entry's own icon when it does not. A generic unrelated image is never
/// substituted, because that would misrepresent the entry.
class _Hero extends StatelessWidget {
  const _Hero({required this.entry, required this.devanagari});

  final Festival entry;
  final bool devanagari;

  static const double _height = 132;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _height,
      width: double.infinity,
      child: FestivalImage(
        assetPath: entry.imagePath,
        height: _height,
        fallback: _Fallback(theme: theme, icon: entry.iconData),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.theme, required this.icon});

  final ThemeData theme;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            theme.colorScheme.primary.withValues(alpha: 0.22),
            theme.colorScheme.tertiary.withValues(alpha: 0.14),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: 46,
          color: theme.colorScheme.primary.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// The day's tithi, computed from the Sun and Moon at Kathmandu sunrise.
///
/// Shown for every day, not only festival days. Ekadashi, Purnima and Aunsi
/// are highlighted because they are the days most people fast or observe.
/// Labelled as computed: festivals kept by an evening or midnight tithi (Laxmi
/// Puja, Shivaratri) can fall on a day whose sunrise tithi is the one before.
class _TithiLine extends StatelessWidget {
  const _TithiLine({required this.gregorian, required this.devanagari});

  final DateTime gregorian;
  final bool devanagari;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final tithi = TithiService.instance.forDate(gregorian);
    final special = tithi.isPurnima || tithi.isAunsi || tithi.isEkadashi;
    final accent = tithi.isPurnima
        ? const Color(0xFFFFB020)
        : tithi.isAunsi
        ? const Color(0xFF7D7AFF)
        : theme.colorScheme.primary;

    return Semantics(
      label: devanagari
          ? 'तिथि ${tithi.label(nepali: true)}'
          : 'Tithi ${tithi.label()}',
      child: Row(
        children: <Widget>[
          Icon(
            tithi.isShukla
                ? Icons.brightness_5_rounded
                : Icons.brightness_3_rounded,
            size: 14,
            color: special ? accent : glass.textSecondary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              devanagari
                  ? '${tithi.label(nepali: true)} • ${tithi.paksha(nepali: true)}'
                  : '${tithi.label()} • ${tithi.paksha()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: special ? accent : glass.textSecondary,
                fontWeight: special ? FontWeight.w600 : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            devanagari ? '(गणना)' : '(computed)',
            style: theme.textTheme.labelSmall?.copyWith(
              color: glass.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
