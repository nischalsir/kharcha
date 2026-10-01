import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/festival_provider.dart';
import '../../core/l10n/app_l10n.dart';
import '../../services/device_locator.dart';
import '../../services/location_service.dart';
import '../../services/nepali_date_service.dart';
import '../../services/weather_service.dart';
import '../../widgets/calendar/bs_month_grid.dart';
import '../../widgets/calendar/day_info_card.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/festival_image.dart';
import '../../widgets/common/glass_card.dart';

/// Bikram Sambat calendar with a month grid and a daily information card.
///
/// The displayed month and the selected day are the only mutable state. Both
/// start at today, and every value shown is derived through [NepaliDateService]
/// so the grid, the weekday, and the Gregorian date always agree with each other.
class FestivalsScreen extends StatefulWidget {
  const FestivalsScreen({super.key});

  @override
  State<FestivalsScreen> createState() => _FestivalsScreenState();
}

class _FestivalsScreenState extends State<FestivalsScreen> {
  BsDate? _selected;
  int? _month;
  int? _year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final dates = context.read<NepaliDateService>();
    final festivals = context.watch<FestivalProvider>();

    final today = dates.today();
    final year = _year ?? today.year;
    final month = _month ?? today.month;
    final selected = _selected ?? today;

    final markedDays = <BsDate>{
      for (final entry in festivals.forYear(year))
        BsDate(entry.bsYear, entry.bsMonth, entry.bsDay),
    };
    // Taken from the service rather than from the entries above, because the
    // gazetted Dashain and Tihar blocks contain days with no named entry.
    final holidayDays = festivals.publicHolidayDays(year);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Calendar', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      dates.formatBs(today, style: BsFormat.full),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: glass.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _TodayButton(
                onPressed: () => setState(() {
                  _selected = today;
                  _month = today.month;
                  _year = today.year;
                }),
              ),
            ],
          ),
          const SizedBox(height: 20),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
            child: Column(
              children: <Widget>[
                _MonthHeader(
                  year: year,
                  month: month,
                  onPrevious: () => _shiftMonth(dates, year, month, -1),
                  onNext: () => _shiftMonth(dates, year, month, 1),
                ),
                const SizedBox(height: 12),
                BsMonthGrid(
                  year: year,
                  month: month,
                  selected: selected,
                  today: today,
                  markedDays: markedDays,
                  publicHolidays: holidayDays,
                  onDaySelected: (day) => setState(() => _selected = day),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DayInfoCard(
            date: selected,
            isToday: selected == today,
            // Only the current conditions are known, so other days show none.
            trailing: selected == today ? const _WeatherBadge() : null,
          ),
          if (!festivals.hasYearData(year)) ...<Widget>[
            const SizedBox(height: 12),
            _YearDataNotice(year: year, devanagari: dates.devanagari),
          ],
          const SizedBox(height: 24),
          _MonthListings(
            year: year,
            month: month,
            onSelectDay: (day) => setState(() => _selected = day),
          ),
        ],
      ),
    );
  }

  /// Moves the visible month and clears the selection, because the previously
  /// selected day belongs to a month that is no longer on screen.
  void _shiftMonth(NepaliDateService dates, int year, int month, int delta) {
    final moved = dates.shiftMonth(BsDate(year, month, 1), delta);
    setState(() {
      _year = moved.year;
      _month = moved.month;
      _selected = null;
    });
  }
}

/// Current weather, shown in the corner of today's information card.
///
/// Uses the same key-less Open-Meteo lookup as the AI mood card. When the
/// coordinates are not configured or the request fails, the badge simply
/// renders nothing, so the calendar is never blocked by the network.
class _WeatherBadge extends StatefulWidget {
  const _WeatherBadge();

  @override
  State<_WeatherBadge> createState() => _WeatherBadgeState();
}

class _WeatherBadgeState extends State<_WeatherBadge> {
  // Shared so reselecting today reuses the cached reading.
  static final WeatherService _service = WeatherService(
    locationService: LocationService(device: const GeolocatorDeviceLocator()),
  );

  static const String _askedKey = 'weather.location_asked';

  AiWeather? _weather;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final weather = await _service.current();
    if (!mounted) return;
    if (weather != null) setState(() => _weather = weather);
    try {
      await _offerLocation();
    } catch (_) {
      // No location or preferences plugin here: the weather stays as it is.
    }
  }

  /// Asks, once, whether the weather may use the phone's location. Until
  /// then (and if the answer is no) the weather is for wherever the network
  /// address suggests, which can be a neighbouring city.
  Future<void> _offerLocation() async {
    if (await GeolocatorDeviceLocator.isPermitted()) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_askedKey) == true || !mounted) return;
    await prefs.setBool(_askedKey, true);
    if (!mounted) return;

    // Said in the app's own words first, so the system prompt that follows
    // is not a surprise.
    final allow = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          dialogContext.t(
            'Weather for where you are?',
            'तपाईं भएको ठाउँको मौसम?',
          ),
        ),
        content: Text(
          dialogContext.t(
            'Kharcha can use your approximate location to show the weather '
                'for your town. It is used for the weather only and is not '
                'saved.',
            'खर्चाले तपाईंको अनुमानित स्थान प्रयोग गरी तपाईंको शहरको मौसम '
                'देखाउन सक्छ। यो मौसमका लागि मात्र प्रयोग हुन्छ र सुरक्षित '
                'गरिँदैन।',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.t('Not now', 'अहिले होइन')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.t('Allow', 'अनुमति दिनुहोस्')),
          ),
        ],
      ),
    );
    if (allow != true) return;
    final weather = await _service.current(askPermission: true);
    if (mounted && weather != null) setState(() => _weather = weather);
  }

  @override
  Widget build(BuildContext context) {
    final weather = _weather;
    if (weather == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final glass = context.glass;
    final devanagari = context.read<NepaliDateService>().devanagari;

    final label = devanagari ? _labelNe(weather.code) : weather.label;
    final place = weather.place;
    return Semantics(
      label:
          '${devanagari ? 'मौसम' : 'Weather'}: '
          '${weather.temperatureC.round()}°C, $label'
          '${place == null ? '' : ', $place'}',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(weather.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 6),
                  Text(
                    '${weather.temperatureC.round()}°C',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: glass.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (place != null) ...<Widget>[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.place_rounded,
                      size: 11,
                      color: glass.textTertiary,
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        place,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: glass.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _labelNe(int code) {
    if (code == 0) return 'सफा मौसम';
    if (code >= 1 && code <= 3) return 'आंशिक बादल';
    if (code >= 51 && code <= 67) return 'वर्षा';
    if (code >= 71 && code <= 77) return 'हिउँदे';
    if (code >= 80 && code <= 82) return 'छिटपुट वर्षा';
    if (code >= 95) return 'आँधी';
    return 'बादल';
  }
}

class _TodayButton extends StatelessWidget {
  const _TodayButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.today_rounded, size: 18),
      label: const Text('Today'),
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.primary,
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.year,
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final int year;
  final int month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dates = context.read<NepaliDateService>();
    return Row(
      children: <Widget>[
        _NavButton(
          icon: Icons.chevron_left_rounded,
          onPressed: onPrevious,
          tooltip: 'Previous month',
        ),
        Expanded(
          child: Column(
            children: <Widget>[
              Text(
                dates.monthName(month, useDevanagari: false),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                '$year BS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: context.glass.textSecondary,
                ),
              ),
            ],
          ),
        ),
        _NavButton(
          icon: Icons.chevron_right_rounded,
          onPressed: onNext,
          tooltip: 'Next month',
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.5,
        ),
      ),
    );
  }
}

/// Shown when the visible year has no gazetted calendar bundled.
///
/// The fixed solar dates are still shown for that year, but the lunar and
/// astrological festivals are not guessed at, so the gap is stated instead of
/// hidden.
class _YearDataNotice extends StatelessWidget {
  const _YearDataNotice({required this.year, required this.devanagari});

  final int year;
  final bool devanagari;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.info_outline_rounded, size: 15, color: glass.textTertiary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            devanagari
                ? '$year को पञ्चाङ्गमूलक तिथिअनुसारका चाडपर्वहरू '
                      'अहिले उपलब्ध छैनन्।'
                : 'The panchang-based festival dates for $year BS have not been '
                      'published yet. Only fixed-date holidays are shown.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: glass.textTertiary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// Public holidays and festivals falling in the visible month.
class _MonthListings extends StatelessWidget {
  const _MonthListings({
    required this.year,
    required this.month,
    required this.onSelectDay,
  });

  final int year;
  final int month;
  final ValueChanged<BsDate> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final dates = context.read<NepaliDateService>();
    final festivals = context.watch<FestivalProvider>();

    if (!festivals.forYear(year).isNotEmpty) {
      return const SizedBox.shrink();
    }

    final inMonth = festivals
        .inMonth(year, month)
        .where((f) => f.bsMonth == month)
        .toList(growable: false);

    if (inMonth.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'In this month',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: EmptyState(
              icon: Icons.event_busy_rounded,
              title: 'Nothing this month',
              message:
                  '${dates.monthName(month)} $year has no festivals '
                  'or public holidays.',
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'In this month',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${inMonth.length} ${inMonth.length == 1 ? "entry" : "entries"}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: glass.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        for (final entry in inMonth)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MonthRow(
              name: entry.title(devanagari: dates.devanagari),
              subtitle: dates.formatBs(
                BsDate(entry.bsYear, entry.bsMonth, entry.bsDay),
                style: BsFormat.long,
              ),
              tithi: entry.tithi,
              icon: entry.iconData,
              imagePath: entry.imagePath,
              isHoliday: entry.isPublicHoliday,
              onTap: () =>
                  onSelectDay(BsDate(entry.bsYear, entry.bsMonth, entry.bsDay)),
            ),
          ),
      ],
    );
  }
}

class _MonthRow extends StatelessWidget {
  const _MonthRow({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.imagePath,
    required this.isHoliday,
    required this.onTap,
    this.tithi,
  });

  static const double _thumb = 46;

  final String name;
  final String subtitle;
  final String? tithi;
  final IconData icon;

  /// The festival's photograph; [icon] is shown when it has none.
  final String imagePath;
  final bool isHoliday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final accent = isHoliday
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: _thumb,
              height: _thumb,
              child: FestivalImage(
                assetPath: imagePath,
                width: _thumb,
                height: _thumb,
                fallback: ColoredBox(
                  color: accent.withValues(alpha: 0.14),
                  child: Center(child: Icon(icon, size: 21, color: accent)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  tithi != null && tithi!.isNotEmpty
                      ? '$subtitle  •  $tithi'
                      : subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: glass.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isHoliday)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Holiday',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
