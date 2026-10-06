import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/theme/app_tokens.dart';
import 'package:kharcha_app/widgets/common/animated_number.dart';
import 'package:kharcha_app/widgets/common/empty_state.dart';
import 'package:kharcha_app/widgets/common/glass_button.dart';
import 'package:kharcha_app/widgets/common/glass_card.dart';
import 'package:kharcha_app/widgets/common/glass_sheet.dart';
import 'package:kharcha_app/widgets/common/grouped_list.dart';
import 'package:kharcha_app/widgets/common/page_header.dart';
import 'package:kharcha_app/widgets/common/pressable_scale.dart';
import 'package:kharcha_app/widgets/common/primary_button.dart';
import 'package:kharcha_app/widgets/common/segmented_switch.dart';
import 'package:kharcha_app/widgets/common/skeleton_loader.dart';
import 'package:kharcha_app/widgets/common/staggered_list_item.dart';

/// The shared pieces every page is built from: what they look like, how they
/// answer a touch, and what they do when motion is turned down.
void main() {
  Widget app(Widget child, {bool dark = false, bool reduceMotion = false}) =>
      MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      );

  /// Holds a finger down on [finder] until the press has landed: past the
  /// moment a touch is known not to be the start of a scroll, one frame for
  /// the spring to start its clock, and then long enough for it to arrive.
  Future<TestGesture> press(WidgetTester tester, Finder finder) async {
    final gesture = await tester.startGesture(tester.getCenter(finder));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));
    return gesture;
  }

  double scaleOf(WidgetTester tester) => tester
      .widget<Transform>(
        find
            .descendant(
              of: find.byType(PressableScale),
              matching: find.byType(Transform),
            )
            .first,
      )
      .transform
      // The scale across the page. (The largest scale on any axis would
      // always be 1: nothing is scaled in depth.)
      .entry(0, 0);

  group('Pressing', () {
    testWidgets('a pressable sinks under the finger and springs back', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        app(
          PressableScale(
            onTap: () => taps++,
            child: const SizedBox(width: 120, height: 60),
          ),
        ),
      );
      expect(scaleOf(tester), 1);

      final gesture = await press(tester, find.byType(PressableScale));
      expect(scaleOf(tester), lessThan(1));
      expect(scaleOf(tester), closeTo(0.98, 0.005));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(scaleOf(tester), 1);
      expect(taps, 1);
    });

    testWidgets('it can be let go and pressed again mid-way without a jump', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          PressableScale(
            onTap: () {},
            child: const SizedBox(width: 120, height: 60),
          ),
        ),
      );
      var gesture = await press(tester, find.byType(PressableScale));
      await gesture.up();
      // Part of the way back up.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 40));
      final midway = scaleOf(tester);
      expect(midway, greaterThan(0.98));
      expect(midway, lessThan(1));

      // Caught again: it turns round from where it is, keeping the speed it
      // had, so the next frame is a hair from the last one. It does not
      // first finish coming up, and it does not snap to either end.
      gesture = await tester.startGesture(
        tester.getCenter(find.byType(PressableScale)),
      );
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump(const Duration(milliseconds: 16));
      expect(scaleOf(tester), closeTo(midway, 0.002));
      await tester.pump(const Duration(milliseconds: 300));
      expect(scaleOf(tester), closeTo(0.98, 0.005));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scaleOf(tester), 1);
    });

    testWidgets('with reduced motion it dims but does not move', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          reduceMotion: true,
          PressableScale(
            onTap: () {},
            child: const SizedBox(width: 120, height: 60),
          ),
        ),
      );
      final gesture = await press(tester, find.byType(PressableScale));
      expect(scaleOf(tester), 1);
      final opacity = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(PressableScale),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, lessThan(1));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('anything tappable is announced as a button', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(GlassCard(onTap: () {}, child: const Text('Open the shop'))),
      );
      expect(
        tester.getSemantics(find.text('Open the shop')),
        isSemantics(label: 'Open the shop', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });
  });

  group('Surfaces', () {
    testWidgets('a card is a flat fill: no blur, and the theme radius', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(const GlassCard(glow: true, strong: true, child: Text('card'))),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      final clip = tester.widget<ClipRRect>(
        find.descendant(
          of: find.byType(GlassCard),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(
        clip.borderRadius,
        BorderRadius.circular(
          tester.element(find.byType(GlassCard)).tokens.radiusCard,
        ),
      );
    });

    Color? fieldFill(WidgetTester tester) =>
        Theme.of(tester.element(find.byType(TextField)))
            .inputDecorationTheme
            .fillColor;

    Color cardFill(WidgetTester tester) =>
        (tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: find.byType(GlassCard),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration)
            .color!;

    for (final dark in <bool>[false, true]) {
      final name = dark ? 'dark' : 'light';
      testWidgets('a field in a card can be told from the card ($name)', (
        tester,
      ) async {
        await tester.pumpWidget(
          app(dark: dark, const GlassCard(child: TextField())),
        );
        expect(fieldFill(tester), isNot(cardFill(tester)));
      });

      testWidgets('on a sheet, fields and cards step off the sheet ($name)', (
        tester,
      ) async {
        await tester.pumpWidget(
          app(
            dark: dark,
            const GlassSheet(
              title: 'Add',
              child: Column(
                children: <Widget>[
                  TextField(key: ValueKey<String>('bare')),
                  GlassCard(child: Text('row')),
                ],
              ),
            ),
          ),
        );
        final sheet = tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byType(GlassSheet),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color;
        expect(fieldFill(tester), isNot(sheet));
        expect(cardFill(tester), isNot(sheet));
        expect(find.byType(BackdropFilter), findsNothing);
      });
    }

    testWidgets('rows in one card are parted by hairlines, not boxes', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          GroupedCard(
            children: <Widget>[
              for (final name in <String>['Rice', 'Oil', 'Salt'])
                GroupedRow(
                  leading: LeadingTile.initial(color: Colors.red, name: name),
                  title: Text(name),
                  trailing: const TrailingAmount(text: 'NPR 10.00'),
                  onTap: () {},
                ),
            ],
          ),
        ),
      );
      expect(find.byType(GlassCard), findsOneWidget);
      expect(find.byType(Divider), findsNWidgets(2));
      // Every row is at least a comfortable touch target.
      for (final row in tester.widgetList(find.byType(GroupedRow))) {
        expect(
          tester.getSize(find.byWidget(row)).height,
          greaterThanOrEqualTo(48),
        );
      }
    });
  });

  group('Colour', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final dark in <bool>[false, true]) {
      testWidgets(
        'gain, warning and loss can be read on a card (${dark ? 'dark' : 'light'})',
        (tester) async {
          late GlassThemeCompat glass;
          late Color card;
          await tester.pumpWidget(
            app(
              dark: dark,
              Builder(
                builder: (context) {
                  glass = context.glass;
                  card = Theme.of(context).colorScheme.surfaceContainerHigh;
                  return const SizedBox();
                },
              ),
            ),
          );
          for (final color in <Color>[
            glass.success,
            glass.warning,
            glass.danger,
          ]) {
            expect(contrast(color, card), greaterThanOrEqualTo(4.5));
          }
        },
      );
    }
  });

  group('Buttons', () {
    testWidgets('an action with only an icon still has a name', (tester) async {
      final handle = tester.ensureSemantics();
      var pressed = 0;
      await tester.pumpWidget(
        app(
          HeaderAction(
            icon: Icons.add_rounded,
            label: 'Add friend',
            showLabel: false,
            onPressed: () => pressed++,
          ),
        ),
      );
      expect(find.text('Add friend'), findsNothing);
      expect(find.byTooltip('Add friend'), findsOneWidget);
      expect(find.bySemanticsLabel('Add friend'), findsOneWidget);
      // 48dp to touch, though it is drawn smaller.
      expect(
        tester.getSize(find.byType(PressableScale)).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.byType(HeaderAction));
      await tester.pumpAndSettle();
      expect(pressed, 1);
      handle.dispose();
    });

    testWidgets('a working button takes no second tap', (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        app(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              PrimaryButton(
                label: 'Save',
                isLoading: true,
                onPressed: () => presses++,
              ),
              GlassButton(
                label: 'Export',
                isLoading: true,
                onPressed: () => presses++,
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.byType(PrimaryButton));
      await tester.tap(find.byType(GlassButton));
      await tester.pump(const Duration(milliseconds: 400));
      expect(presses, 0);
    });
  });

  group('Loading', () {
    Widget placeholder() => const SkeletonList(count: 2, label: 'Loading rows');

    testWidgets('a skeleton is announced once and its boxes are not read', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(placeholder()));
      expect(find.bySemanticsLabel('Loading rows'), findsOneWidget);
      expect(find.byType(SkeletonRow), findsNWidgets(2));
      expect(tester.hasRunningAnimations, isTrue);
      handle.dispose();
    });

    testWidgets('with reduced motion a skeleton holds still', (tester) async {
      await tester.pumpWidget(app(reduceMotion: true, placeholder()));
      // Nothing left to animate: this would time out on a pulsing skeleton.
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byType(SkeletonRow), findsNWidgets(2));
    });

    testWidgets('a placeholder row is laid out like the row it stands for', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          reduceMotion: true,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Skeleton(
                child: SkeletonRow(key: ValueKey<String>('ghost')),
              ),
              GroupedRow(
                key: const ValueKey<String>('real'),
                leading: const LeadingTile(
                  color: Colors.red,
                  icon: Icons.north_east,
                ),
                title: const Text('Groceries'),
                subtitle: const Text('Cash'),
                trailing: const TrailingAmount(text: '-NPR 500.00'),
              ),
            ],
          ),
        ),
      );
      final ghost = tester.getSize(find.byKey(const ValueKey<String>('ghost')));
      final real = tester.getSize(find.byKey(const ValueKey<String>('real')));
      // The content arriving moves nothing: same height, to the pixel or two
      // a line of text differs from the block standing in for it.
      expect((ghost.height - real.height).abs(), lessThanOrEqualTo(4));
    });

    testWidgets('the placeholder gives way to the content when it arrives', (
      tester,
    ) async {
      Widget page(bool loading) => app(
        reduceMotion: true,
        SkeletonSwitcher(
          loading: loading,
          skeleton: placeholder(),
          child: const Text('3 backups'),
        ),
      );
      await tester.pumpWidget(page(true));
      expect(find.byType(SkeletonRow), findsNWidgets(2));
      expect(find.text('3 backups'), findsNothing);

      await tester.pumpWidget(page(false));
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonRow), findsNothing);
      expect(find.text('3 backups'), findsOneWidget);
    });

    testWidgets('failing to load is not shown as having nothing', (
      tester,
    ) async {
      var retries = 0;
      await tester.pumpWidget(
        app(
          ErrorState(
            title: 'Could not load your backups',
            message: 'Check your connection and try again.',
            retryLabel: 'Try again',
            onRetry: () => retries++,
          ),
        ),
      );
      expect(find.text('Could not load your backups'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(retries, 1);
    });

    testWidgets('an empty list says so and offers the way to fill it', (
      tester,
    ) async {
      var added = 0;
      await tester.pumpWidget(
        app(
          EmptyState(
            icon: Icons.people_outline,
            title: 'No friends yet',
            message: 'Add a friend to track money you lend or borrow.',
            actionLabel: 'Add Friend',
            onAction: () => added++,
          ),
        ),
      );
      expect(find.text('No friends yet'), findsOneWidget);
      await tester.tap(find.text('Add Friend'));
      await tester.pumpAndSettle();
      expect(added, 1);
    });
  });

  group('Motion', () {
    testWidgets('a figure is shown at once and only rolls when it changes', (
      tester,
    ) async {
      Widget figure(double value) => app(
        AnimatedNumber(value: value, formatter: (v) => v.toStringAsFixed(0)),
      );
      await tester.pumpWidget(figure(1234));
      // No counting up from zero on the way in.
      expect(find.text('1234'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(figure(2000));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('2000'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('2000'), findsOneWidget);
    });

    testWidgets('a changed figure does not roll when motion is reduced', (
      tester,
    ) async {
      Widget figure(double value) => app(
        reduceMotion: true,
        AnimatedNumber(value: value, formatter: (v) => v.toStringAsFixed(0)),
      );
      await tester.pumpWidget(figure(1234));
      await tester.pumpWidget(figure(2000));
      await tester.pump();
      expect(find.text('2000'), findsOneWidget);
    });

    double rowOpacity(WidgetTester tester) => tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(StaggeredListItem),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;

    testWidgets('a row arrives once, not again each time it scrolls back', (
      tester,
    ) async {
      Widget page(int build) => app(
        StaggeredListItem(
          // A new key is what scrolling away and back does to a row.
          key: ValueKey<int>(build),
          index: 0,
          child: const Text('row'),
        ),
      );
      await tester.pumpWidget(page(0));
      expect(rowOpacity(tester), lessThan(1));
      await tester.pumpAndSettle();
      expect(rowOpacity(tester), 1);

      await tester.pumpWidget(page(1));
      expect(rowOpacity(tester), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('with reduced motion a row is simply there', (tester) async {
      await tester.pumpWidget(
        app(
          reduceMotion: true,
          const StaggeredListItem(index: 0, child: Text('row')),
        ),
      );
      expect(rowOpacity(tester), 1);
    });
  });

  group('Switch', () {
    Widget switcher({
      required ValueChanged<int> onChanged,
      bool reduceMotion = false,
      int start = 0,
    }) {
      var value = start;
      return app(
        reduceMotion: reduceMotion,
        Padding(
          padding: const EdgeInsets.all(20),
          child: StatefulBuilder(
            builder: (context, setState) => SegmentedSwitch<int>(
              segments: const <SwitchSegment<int>>[
                SwitchSegment<int>(value: 0, label: 'Friends'),
                SwitchSegment<int>(value: 1, label: 'Pasal'),
              ],
              selected: value,
              onChanged: (next) {
                setState(() => value = next);
                onChanged(next);
              },
            ),
          ),
        ),
      );
    }

    /// Where the thumb starts, from the left edge of the control.
    double thumbLeft(WidgetTester tester) => tester
        .widget<Positioned>(
          find
              .descendant(
                of: find.byType(SegmentedSwitch<int>),
                matching: find.byType(Positioned),
              )
              .first,
        )
        .left!;

    testWidgets('a tap sends the thumb to that segment and says so', (
      tester,
    ) async {
      final chosen = <int>[];
      await tester.pumpWidget(switcher(onChanged: chosen.add));
      final start = thumbLeft(tester);

      await tester.tap(find.text('Pasal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // On its way: neither where it was nor where it is going.
      final midway = thumbLeft(tester);
      expect(midway, greaterThan(start));
      await tester.pumpAndSettle();
      expect(thumbLeft(tester), greaterThan(midway));
      expect(chosen, <int>[1]);

      // Tapping where it already is asks for nothing.
      await tester.tap(find.text('Pasal'));
      await tester.pumpAndSettle();
      expect(chosen, <int>[1]);
    });

    testWidgets('the thumb can be dragged across and stays where it is left', (
      tester,
    ) async {
      final chosen = <int>[];
      await tester.pumpWidget(switcher(onChanged: chosen.add));
      final width = tester.getSize(find.byType(SegmentedSwitch<int>)).width;
      final from = tester.getCenter(find.text('Friends'));

      final gesture = await tester.startGesture(from);
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      final start = thumbLeft(tester);
      // Glued to the finger: it moves exactly as far as the finger does.
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(thumbLeft(tester) - start, closeTo(40, 0.5));
      // Nothing is chosen until it is let go.
      expect(chosen, isEmpty);

      await gesture.moveBy(Offset(width / 2, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(chosen, <int>[1]);
    });

    testWidgets('a short pull that is let go springs back', (tester) async {
      final chosen = <int>[];
      await tester.pumpWidget(switcher(onChanged: chosen.add));
      final rest = thumbLeft(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Friends')),
      );
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      expect(thumbLeft(tester), greaterThan(rest));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(thumbLeft(tester), closeTo(rest, 0.01));
      expect(chosen, isEmpty);
    });

    testWidgets('past the end it resists instead of leaving the track', (
      tester,
    ) async {
      await tester.pumpWidget(switcher(onChanged: (_) {}, start: 1));
      final rest = thumbLeft(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Pasal')),
      );
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      // Pressed against the end: it has given a little, far less than the
      // finger travelled, and has not gone anywhere.
      expect(thumbLeft(tester) - rest, inInclusiveRange(0, 30));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(thumbLeft(tester), closeTo(rest, 0.01));
    });

    testWidgets('with reduced motion the thumb is simply there', (
      tester,
    ) async {
      final chosen = <int>[];
      await tester.pumpWidget(
        switcher(onChanged: chosen.add, reduceMotion: true),
      );
      final start = thumbLeft(tester);
      await tester.tap(find.text('Pasal'));
      await tester.pump();
      expect(chosen, <int>[1]);
      expect(thumbLeft(tester), greaterThan(start + 50));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('each segment is a button that says whether it is chosen', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(switcher(onChanged: (_) {}));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Friends')),
        isSemantics(
          label: 'Friends',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Pasal')),
        isSemantics(
          label: 'Pasal',
          isButton: true,
          isSelected: false,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });
}
