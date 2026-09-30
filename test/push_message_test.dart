import 'package:kharcha_app/core/router/route_paths.dart';
import 'package:kharcha_app/models/push_category.dart';
import 'package:kharcha_app/models/push_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PushMessage.fromData', () {
    test('parses a well-formed payload', () {
      final message = PushMessage.fromData(<String, dynamic>{
        'title': 'Budget at risk',
        'body': 'You have spent 82% of your food budget',
        'category': 'budget_warnings',
        'route': RoutePaths.budgets,
      });

      expect(message, isNotNull);
      expect(message!.title, 'Budget at risk');
      expect(message.body, 'You have spent 82% of your food budget');
      expect(message.category, 'budget_warnings');
      expect(message.route, RoutePaths.budgets);
      expect(message.channel, PushChannel.budget);
      expect(message.resolvedCategory?.id, 'budget_warnings');
    });

    test('rejects a payload missing any required field', () {
      const full = <String, dynamic>{
        'title': 't',
        'body': 'b',
        'category': 'budget_warnings',
      };
      for (final missing in full.keys) {
        final data = Map<String, dynamic>.of(full)..remove(missing);
        expect(
          PushMessage.fromData(data),
          isNull,
          reason: 'a payload without "$missing" is not renderable',
        );
      }
    });

    test('rejects blank required fields', () {
      expect(
        PushMessage.fromData(<String, dynamic>{
          'title': '   ',
          'body': 'b',
          'category': 'budget_warnings',
        }),
        isNull,
      );
    });

    test('an AI push resolves to the insights channel', () {
      // The digest worker labels every AI push "ai_content" regardless of what
      // the insight was about. That is deliberate: a topic label like "budget"
      // is not a push category, so it resolves to nothing and the notification
      // lands in the general channel. This test fails if that split regresses.
      final message = PushMessage.fromData(<String, dynamic>{
        'title': 'Spending is up',
        'body': 'You spent 40% more on food this week',
        'category': 'ai_content',
      });

      expect(message, isNotNull);
      expect(message!.resolvedCategory, PushCategory.aiContent);
      expect(message.channel, PushChannel.insights);
      expect(message.importance, PushImportance.low);
    });

    test('keeps an unknown category so it still shows in the fallback channel', () {
      // A newer server may add a category this build has never heard of. The
      // notification must still appear rather than vanish.
      final message = PushMessage.fromData(<String, dynamic>{
        'title': 'New thing',
        'body': 'b',
        'category': 'from-the-future',
      });

      expect(message, isNotNull);
      expect(message!.channel, PushChannel.fallback);
      expect(message.importance, PushImportance.defaultImportance);
    });

    test('non-string data values are coerced, because FCM data is string-only', () {
      final message = PushMessage.fromData(<String, dynamic>{
        'title': 't',
        'body': 'b',
        'category': 'budget_warnings',
        'some_number': 42,
      });
      expect(message!.data['some_number'], '42');
    });

    test('required fields are not duplicated into the extras map', () {
      final message = PushMessage.fromData(<String, dynamic>{
        'title': 't',
        'body': 'b',
        'category': 'budget_warnings',
      });
      expect(message!.data.containsKey('title'), isFalse);
      expect(message.data.containsKey('body'), isFalse);
      expect(message.data.containsKey('category'), isFalse);
    });
  });

  group('route_args', () {
    test('decodes a JSON string argument', () {
      final message = PushMessage.fromData(<String, dynamic>{
        'title': 't',
        'body': 'b',
        'category': 'budget_warnings',
        'route': RoutePaths.friendDetail,
        'route_args': '"friend-42"',
      });
      expect(message!.routeArgs, 'friend-42');
    });

    test('decodes a bare integer argument', () {
      final message = PushMessage.fromData(<String, dynamic>{
        'title': 't',
        'body': 'b',
        'category': 'budget_warnings',
        'route': RoutePaths.friendDetail,
        'route_args': '42',
      });
      expect(message!.routeArgs, '42');
    });

    test('a malformed argument degrades to no argument rather than throwing', () {
      // The tap target matters more than the id: dropping the argument still
      // opens something, whereas throwing here would lose the tap entirely.
      final message = PushMessage.fromData(<String, dynamic>{
        'title': 't',
        'body': 'b',
        'category': 'budget_warnings',
        'route': RoutePaths.friendDetail,
        'route_args': '{not valid json',
      });
      expect(message!.routeArgs, isNull);
      expect(message.route, RoutePaths.friendDetail);
    });
  });

  group('RoutePaths.isKnown', () {
    test('accepts every declared route', () {
      for (final route in RoutePaths.all) {
        expect(RoutePaths.isKnown(route), isTrue, reason: route);
      }
    });

    test('rejects a route the app cannot resolve', () {
      // pushNamed on an unknown name throws rather than doing nothing, and a
      // push payload is not trusted input.
      expect(RoutePaths.isKnown('/definitely-not-a-screen'), isFalse);
      expect(RoutePaths.isKnown(''), isFalse);
      expect(RoutePaths.isKnown(null), isFalse);
    });
  });
}
