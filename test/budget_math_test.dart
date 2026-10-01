import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/utils/budget_math.dart';

void main() {
  group('startOfWeek (Sunday-based, as in Nepal)', () {
    test('a mid-week day goes back to Sunday at midnight', () {
      // 2026-10-01 is a Thursday.
      expect(startOfWeek(DateTime(2026, 10, 1, 15, 30)), DateTime(2026, 9, 27));
    });

    test('Sunday is its own start', () {
      expect(startOfWeek(DateTime(2026, 9, 27, 23, 59)), DateTime(2026, 9, 27));
    });

    test('Saturday belongs to the week that began six days earlier', () {
      expect(startOfWeek(DateTime(2026, 10, 3)), DateTime(2026, 9, 27));
    });
  });

  group('dailyAllowance', () {
    test('spreads what is left over the days left', () {
      expect(dailyAllowance(remaining: 3000, daysLeft: 10), 300);
    });

    test('is nothing once the budget is used up', () {
      expect(dailyAllowance(remaining: 0, daysLeft: 10), isNull);
      expect(dailyAllowance(remaining: -500, daysLeft: 10), isNull);
    });

    test('is nothing when no days are left to spread over', () {
      expect(dailyAllowance(remaining: 3000, daysLeft: 0), isNull);
    });
  });
}
