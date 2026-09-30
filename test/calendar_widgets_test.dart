import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/providers/festival_provider.dart';
import 'package:kharcha_app/screens/festivals/festivals_screen.dart';
import 'package:kharcha_app/services/festival_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/widgets/calendar/day_info_card.dart';

/// A [NepaliDateService] whose "today" is pinned, so the calendar screen can be
/// tested deterministically instead of against the wall clock.
class _FixedTodayService extends NepaliDateService {
  _FixedTodayService(this._today) : super();

  final BsDate _today;

  @override
  BsDate today() => _today;
}

Widget _wrap({
  required NepaliDateService dates,
  required Widget child,
  bool scroll = false,
}) {
  final service = FestivalService(dates);
  if (scroll) child = SingleChildScrollView(child: child);
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: MultiProvider(
        providers: [
          Provider<NepaliDateService>.value(value: dates),
          ChangeNotifierProvider<FestivalProvider>.value(
            value: FestivalProvider(service: service, dates: dates),
          ),
        ],
        child: child,
      ),
    ),
  );
}

/// Enlarges the test viewport so the scrollable calendar screen builds its whole
/// list and offscreen entries are findable.
void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  final dates = NepaliDateService();

  group('DayInfoCard', () {
    testWidgets('a block-only holiday day shows the block name', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          dates: dates,
          scroll: true,
          child: const DayInfoCard(date: BsDate(2083, 7, 2)),
        ),
      );

      expect(find.text('Dashain Holiday'), findsOneWidget);
      expect(find.text('No named festival on this day.'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a named public holiday shows its entry and the badge', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          dates: dates,
          scroll: true,
          child: const DayInfoCard(date: BsDate(2083, 7, 4)),
        ),
      );

      // The name appears twice: in the holiday strip and in the entry tile.
      expect(find.text('Vijaya Dashami'), findsNWidgets(2));
      expect(find.text('Public holiday'), findsOneWidget);
      expect(find.textContaining('Scope:'), findsNothing);
    });

    testWidgets('a regionally scoped holiday records where it applies', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          dates: dates,
          scroll: true,
          child: const DayInfoCard(date: BsDate(2083, 6, 9)),
        ),
      );

      expect(find.text('Indra Jatra'), findsNWidgets(2));
      expect(find.text('Scope: Kathmandu Valley only'), findsOneWidget);
    });

    testWidgets('a lunar entry states the year its date was published for', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          dates: dates,
          scroll: true,
          child: const DayInfoCard(date: BsDate(2083, 5, 12)),
        ),
      );

      expect(find.text('Janai Purnima'), findsNWidgets(2));
      expect(find.text('Panchang date published for BS 2083.'), findsOneWidget);
    });

    testWidgets('a fixed date entry does not claim a panchang date', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          dates: dates,
          scroll: true,
          child: const DayInfoCard(date: BsDate(2083, 1, 1)),
        ),
      );

      expect(find.text('Nepali New Year'), findsNWidgets(2));
      expect(find.textContaining('Panchang date'), findsNothing);
    });

    testWidgets('an ordinary day explains that nothing falls on it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          dates: dates,
          scroll: true,
          child: const DayInfoCard(date: BsDate(2083, 1, 2)),
        ),
      );

      expect(find.text('No festival or holiday on this day.'), findsOneWidget);
    });

    testWidgets('two observances sharing a day both show', (tester) async {
      await tester.pumpWidget(
        _wrap(
          dates: dates,
          scroll: true,
          child: const DayInfoCard(date: BsDate(2083, 7, 22)),
        ),
      );

      expect(find.text('Kukur Tihar'), findsNWidgets(2));
      expect(find.text('Laxmi Puja'), findsNWidgets(2));
    });
  });

  group('FestivalsScreen', () {
    testWidgets('a gazetted year shows no data notice', (tester) async {
      _tallViewport(tester);
      final service = _FixedTodayService(const BsDate(2083, 6, 1));
      await tester.pumpWidget(
        _wrap(dates: service, child: const FestivalsScreen()),
      );

      expect(find.text('Calendar'), findsOneWidget);
      expect(find.textContaining('have not been published yet'), findsNothing);
    });

    testWidgets('a year without gazetted data explains the gap', (
      tester,
    ) async {
      _tallViewport(tester);
      final service = _FixedTodayService(const BsDate(2082, 1, 1));
      await tester.pumpWidget(
        _wrap(dates: service, child: const FestivalsScreen()),
      );

      expect(
        find.textContaining('2082 BS have not been published'),
        findsOneWidget,
      );
      // The fixed solar dates are still shown, so the year is not empty.
      expect(find.textContaining('New Year'), findsWidgets);
    });

    testWidgets('month listings only carry named entries for that month', (
      tester,
    ) async {
      _tallViewport(tester);
      final service = _FixedTodayService(const BsDate(2083, 6, 1));
      await tester.pumpWidget(
        _wrap(dates: service, child: const FestivalsScreen()),
      );

      // Ashwin 2083 contains named entries, including the start of Dashain.
      expect(find.text('Constitution Day'), findsWidgets);
      expect(find.text('Ghatasthapana'), findsWidgets);
    });

    testWidgets(
      'tapping a month row selects that day in the information card',
      (tester) async {
        _tallViewport(tester);
        final service = _FixedTodayService(const BsDate(2083, 6, 1));
        await tester.pumpWidget(
          _wrap(dates: service, child: const FestivalsScreen()),
        );

        // The listing and the empty state both exist first; after selection the
        // day card adds a second rendering of Ghatasthapana.
        await tester.tap(find.text('Ghatasthapana').first);
        await tester.pumpAndSettle();

        // The listing, the holiday strip and the entry tile all show it now.
        expect(find.text('Ghatasthapana'), findsNWidgets(3));
      },
    );

    testWidgets('the Today button restores the selected day', (tester) async {
      _tallViewport(tester);
      final service = _FixedTodayService(const BsDate(2083, 6, 14));
      await tester.pumpWidget(
        _wrap(dates: service, child: const FestivalsScreen()),
      );

      expect(find.text('Today'), findsWidgets);

      await tester.tap(find.text('Ghatasthapana').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Today').last);
      await tester.pumpAndSettle();

      // Back on Ashwin 14: the day card shows no entries for that day.
      expect(find.text('No festival or holiday on this day.'), findsOneWidget);
    });
  });
}
