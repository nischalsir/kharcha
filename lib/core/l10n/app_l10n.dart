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

  /// Reads the language through [LanguageScope] so the calling widget is
  /// rebuilt when it changes. A plain `context.read` never subscribes, which is
  /// why switching language used to leave most of the screen in the old one
  /// until something unrelated rebuilt it.
  static bool isNepali(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_LanguageInherited>();
    return scope?.nepali ?? context.read<NepaliDateService>().devanagari;
  }

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

/// Publishes the active language (and calendar) to the whole app and makes a
/// switch take effect on the very next frame.
///
/// Two mechanisms, because the app reads these settings two ways:
///  * `context.t(...)` depends on the inherited widget below, so those texts
///    rebuild through normal inheritance;
///  * dates are formatted by [NepaliDateService], which ~17 widgets read with
///    `context.read` and which cannot notify. For those, a change marks every
///    element below dirty once. It happens only when the user flips the
///    setting, and it keeps all state (tabs, scroll, open routes).
class LanguageScope extends StatefulWidget {
  const LanguageScope({
    super.key,
    required this.nepali,
    this.calendar = '',
    required this.child,
  });

  final bool nepali;

  /// Any value identifying the calendar system; a change triggers a refresh.
  final Object calendar;
  final Widget child;

  @override
  State<LanguageScope> createState() => _LanguageScopeState();
}

class _LanguageScopeState extends State<LanguageScope> {
  @override
  void didUpdateWidget(LanguageScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nepali != widget.nepali ||
        oldWidget.calendar != widget.calendar) {
      void markAll(Element element) {
        element.markNeedsBuild();
        element.visitChildren(markAll);
      }

      (context as Element).visitChildren(markAll);
    }
  }

  @override
  Widget build(BuildContext context) =>
      _LanguageInherited(nepali: widget.nepali, child: widget.child);
}

class _LanguageInherited extends InheritedWidget {
  const _LanguageInherited({required this.nepali, required super.child});

  final bool nepali;

  @override
  bool updateShouldNotify(_LanguageInherited oldWidget) =>
      oldWidget.nepali != nepali;
}
