import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../services/nepali_date_service.dart';

/// Minimal UI localization for Kharcha.
///
/// Nepali mode is driven by the existing Language setting, which the settings
/// provider mirrors onto [NepaliDateService.devanagari]. Widgets call
/// `context.t('Home', 'गृह')` — English when the language is English, Nepali
/// when it is set to Nepali.
class L10n {
  const L10n._();

  static bool isNepali(BuildContext context) =>
      context.read<NepaliDateService>().devanagari;

  static String t(BuildContext context, String en, String ne) =>
      isNepali(context) ? ne : en;

  /// Time-of-day greeting in the active language.
  ///
  /// Reads the language through the inherited widget, so it may only be called
  /// from `build` or `didChangeDependencies`. Widgets that resolve the greeting
  /// outside a build (a timer, for instance) should capture the language first
  /// and use [timeGreetingFor] instead.
  static String timeGreeting(BuildContext context) => timeGreetingFor(
      hour: DateTime.now().hour, nepali: isNepali(context));

  /// Same greeting, for callers that already know the language.
  static String timeGreetingFor({required int hour, required bool nepali}) {
    if (hour < 5) return nepali ? 'शुभ रात्री' : 'Good night';
    if (hour < 12) return nepali ? 'शुभ प्रभात' : 'Good morning';
    if (hour < 17) return nepali ? 'शुभ दिउँसो' : 'Good afternoon';
    if (hour < 21) return nepali ? 'शुभ साँझ' : 'Good evening';
    return nepali ? 'शुभ रात्री' : 'Good night';
  }

  /// Nepali numeral string for a western [value].
  static String neNumber(Object value) {
    const digits = <String, String>{
      '0': '०',
      '1': '१',
      '2': '२',
      '3': '३',
      '4': '४',
      '5': '५',
      '6': '६',
      '7': '७',
      '8': '८',
      '9': '९',
    };
    return value.toString().split('').map((c) => digits[c] ?? c).join();
  }
}

extension L10nContext on BuildContext {
  bool get isNepali => L10n.isNepali(this);

  /// English/Nepali string pair for the active language.
  String t(String en, String ne) => L10n.t(this, en, ne);
}

