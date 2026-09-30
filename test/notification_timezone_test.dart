import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/models/app_settings_model.dart';

void main() {
  group('NotificationPrefs time zone reporting', () {
    test('defaults to unreported rather than to UTC', () {
      const prefs = NotificationPrefs();
      expect(prefs.utcOffsetMinutes, isNull);
    });

    test("Nepal's half-hour offset survives a round trip", () {
      // +5:45 is the case a whole-hour offset or an hour-only field cannot
      // express, and it is the app's home market.
      const prefs = NotificationPrefs(utcOffsetMinutes: 345);

      final decoded = NotificationPrefs.fromJson(prefs.toJson());

      expect(decoded.utcOffsetMinutes, 345);
    });

    test('a real UTC device is distinguishable from an unreported one', () {
      // Collapsing these would make every UTC user re-report on every launch
      // forever, because the guard could never see the value change.
      const onUtc = NotificationPrefs(utcOffsetMinutes: 0);

      final decoded = NotificationPrefs.fromJson(onUtc.toJson());

      expect(decoded.utcOffsetMinutes, 0);
      expect(NotificationPrefs.fromJson(<String, dynamic>{}).utcOffsetMinutes, isNull);
    });

    test('a negative offset survives a round trip', () {
      const prefs = NotificationPrefs(utcOffsetMinutes: -300);

      expect(NotificationPrefs.fromJson(prefs.toJson()).utcOffsetMinutes, -300);
    });

    test('an unreported offset is omitted rather than written as zero', () {
      expect(const NotificationPrefs().toJson(), isNot(contains('utc_offset_minutes')));
    });

    test('a malformed offset degrades to unreported instead of throwing', () {
      final decoded = NotificationPrefs.fromJson(<String, dynamic>{
        'utc_offset_minutes': 'not a number',
      });

      expect(decoded.utcOffsetMinutes, isNull);
    });

    test('copyWith sets the offset without disturbing the flags', () {
      const prefs = NotificationPrefs(aiContent: true);
      final updated = prefs.copyWith(utcOffsetMinutes: 345);

      expect(updated.utcOffsetMinutes, 345);
      expect(updated.aiContent, isTrue);
    });

    test('a JSON number that is not an int is coerced', () {
      final decoded = NotificationPrefs.fromJson(<String, dynamic>{
        'utc_offset_minutes': 345.0,
      });

      expect(decoded.utcOffsetMinutes, 345);
    });
  });
}
