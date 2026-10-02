import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/router/route_paths.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/models/push_message.dart';
import 'package:kharcha_app/providers/notification_inbox_provider.dart';
import 'package:kharcha_app/screens/notifications/notifications_screen.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/notification_inbox.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

PushMessage _message(String title, {String body = 'body', String? route}) {
  return PushMessage(
    category: 'budget_warnings',
    title: title,
    body: body,
    data: <String, String>{'route': ?route},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('the inbox', () {
    test('keeps what was shown, newest first and unread', () async {
      await NotificationInbox.record(
        _message('First', route: RoutePaths.budgets),
        at: DateTime(2026, 10, 2, 9),
      );
      await NotificationInbox.record(
        _message('Second'),
        at: DateTime(2026, 10, 2, 10),
      );
      final items = await NotificationInbox.load();
      expect(items.map((i) => i.title), <String>['Second', 'First']);
      expect(items.every((i) => !i.read), isTrue);
      expect(items.last.route, RoutePaths.budgets);
      expect(items.last.receivedAt, DateTime(2026, 10, 2, 9));
    });

    test('the same notification raised again is kept once', () async {
      final at = DateTime(2026, 10, 2, 9);
      await NotificationInbox.record(_message('Update available'), at: at);
      // Every launch, until the app is updated.
      await NotificationInbox.record(
        _message('Update available'),
        at: at.add(const Duration(days: 3)),
      );
      expect(await NotificationInbox.load(), hasLength(1));

      // Read, and long enough ago: it is news again.
      await NotificationInbox.markRead();
      await NotificationInbox.record(
        _message('Update available'),
        at: at.add(const Duration(hours: 1)),
      );
      expect(await NotificationInbox.load(), hasLength(1));
      await NotificationInbox.record(
        _message('Update available'),
        at: at.add(const Duration(days: 4)),
      );
      expect(await NotificationInbox.load(), hasLength(2));
    });

    test('reading one, reading all, and emptying', () async {
      for (var i = 0; i < 3; i++) {
        await NotificationInbox.record(
          _message('N$i'),
          at: DateTime(2026, 10, 2, 9, i),
        );
      }
      final first = (await NotificationInbox.load()).first;
      await NotificationInbox.markRead(id: first.id);
      var items = await NotificationInbox.load();
      expect(items.where((i) => i.read).map((i) => i.title), <String>['N2']);

      await NotificationInbox.markRead();
      items = await NotificationInbox.load();
      expect(items.every((i) => i.read), isTrue);

      await NotificationInbox.clear();
      expect(await NotificationInbox.load(), isEmpty);
    });

    test('only the latest hundred are kept', () async {
      for (var i = 0; i < NotificationInbox.capacity + 5; i++) {
        await NotificationInbox.record(
          _message('N$i'),
          at: DateTime(2026, 1, 1).add(Duration(minutes: i)),
        );
      }
      final items = await NotificationInbox.load();
      expect(items, hasLength(NotificationInbox.capacity));
      expect(items.first.title, 'N${NotificationInbox.capacity + 4}');
      expect(items.last.title, 'N5');
    });

    test('a damaged list is treated as empty, not as a crash', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'notifications.inbox': '{not json',
      });
      expect(await NotificationInbox.load(), isEmpty);
      await NotificationInbox.record(_message('After'));
      expect(await NotificationInbox.load(), hasLength(1));
    });
  });

  group('the bell and the sheet', () {
    Future<NotificationInboxProvider> pump(
      WidgetTester tester, {
      int unread = 2,
      int read = 0,
    }) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      late NotificationInboxProvider inbox;
      await tester.runAsync(() async {
        final now = DateTime.now();
        for (var i = 0; i < read; i++) {
          await NotificationInbox.record(
            _message('Old $i', body: 'Read before'),
            at: now.subtract(Duration(days: 2, minutes: i)),
          );
        }
        if (read > 0) await NotificationInbox.markRead();
        if (unread > 1) {
          await NotificationInbox.record(
            _message('Rent is due', body: 'Tomorrow'),
            at: now.subtract(const Duration(hours: 3)),
          );
        }
        if (unread > 0) {
          await NotificationInbox.record(
            _message('Budget almost used', body: '90% of Food is spent'),
            at: now.subtract(const Duration(minutes: 5)),
          );
        }
        inbox = NotificationInboxProvider();
        await inbox.refresh();
      });
      addTearDown(inbox.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
            ChangeNotifierProvider<NotificationInboxProvider>.value(
              value: inbox,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: NotificationBell(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return inbox;
    }

    /// Lets the inbox's writes finish, then redraws.
    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey<String>('notification-bell')));
      await settle(tester);
    }

    Future<void> closeSheet(WidgetTester tester) async {
      // A tap on the shade above the sheet.
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
      await settle(tester);
    }

    /// From the sheet's title to the bottom of the screen.
    double sheetHeight(WidgetTester tester) =>
        800 - tester.getTopLeft(find.text('Notifications')).dy;

    testWidgets('the bell counts what has not been read', (tester) async {
      final inbox = await pump(tester);
      expect(inbox.unreadCount, 2);
      expect(find.text('2'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
    });

    testWidgets('it rises over Home, new ones lit, and closing reads them', (
      tester,
    ) async {
      final inbox = await pump(tester);
      await openSheet(tester);

      // Still on Home: the bell is under the sheet's shade, not replaced.
      expect(
        find.byKey(const ValueKey<String>('notification-bell')),
        findsOneWidget,
      );
      expect(find.text('Budget almost used'), findsOneWidget);
      expect(find.text('90% of Food is spent'), findsOneWidget);
      expect(find.text('5 min ago'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);
      expect(find.text('EARLIER'), findsNothing);
      for (final item in inbox.items) {
        expect(
          find.byKey(ValueKey<String>('notification-dot-${item.id}')),
          findsOneWidget,
        );
      }
      expect(find.text('Mark all as read'), findsOneWidget);

      await closeSheet(tester);
      expect(find.text('Notifications'), findsNothing);
      expect(inbox.unreadCount, 0);
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('a line separates the new from the earlier', (tester) async {
      await pump(tester, unread: 1, read: 1);
      await openSheet(tester);

      expect(find.text('NEW'), findsOneWidget);
      expect(find.text('EARLIER'), findsOneWidget);
      final line = find.byKey(const ValueKey<String>('notifications-divider'));
      expect(line, findsOneWidget);
      // New above the line, earlier below it.
      final lineY = tester.getCenter(line).dy;
      expect(
        tester.getCenter(find.text('Budget almost used')).dy,
        lessThan(lineY),
      );
      expect(tester.getCenter(find.text('Old 0')).dy, greaterThan(lineY));
      await closeSheet(tester);
    });

    testWidgets('Mark all as read clears the highlights at once', (
      tester,
    ) async {
      final inbox = await pump(tester);
      await openSheet(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('notifications-read-all')),
      );
      await settle(tester);
      expect(inbox.unreadCount, 0);
      for (final item in inbox.items) {
        expect(
          find.byKey(ValueKey<String>('notification-dot-${item.id}')),
          findsNothing,
        );
      }
      // Nothing left to mark, and nothing new: only earlier ones.
      expect(find.text('Mark all as read'), findsNothing);
      expect(find.text('NEW'), findsNothing);
      expect(find.text('EARLIER'), findsOneWidget);
      expect(find.text('Rent is due'), findsOneWidget);
      await closeSheet(tester);
    });

    testWidgets('a few notifications come up to the middle', (tester) async {
      await pump(tester, unread: 1);
      await openSheet(tester);
      // Half the 800-high screen, less the handle above the title.
      expect(sheetHeight(tester), closeTo(400, 30));
      await closeSheet(tester);
    });

    testWidgets('many notifications stop below the name on Home', (
      tester,
    ) async {
      await pump(tester, unread: 2, read: 14);
      await openSheet(tester);
      final height = sheetHeight(tester);
      expect(height, greaterThan(600));
      // The greeting and the name stay in sight above it.
      expect(height, lessThanOrEqualTo(800 - 96));
      // The rest scrolls inside the sheet.
      expect(
        find.byKey(const ValueKey<String>('notifications-list')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await closeSheet(tester);
    });

    testWidgets('with nothing kept, the sheet says so', (tester) async {
      await pump(tester, unread: 0);
      await openSheet(tester);
      expect(find.text('No notifications'), findsOneWidget);
      expect(find.text('Mark all as read'), findsNothing);
      await closeSheet(tester);
    });
  });
}
