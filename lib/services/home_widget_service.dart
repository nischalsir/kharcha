import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/router/route_paths.dart';

/// What the home-screen widget shows, as ready-made text.
@immutable
class HomeWidgetData {
  const HomeWidgetData({
    required this.day,
    required this.today,
    required this.zero,
    required this.month,
    required this.label,
    required this.add,
    this.monthTitle = '',
    this.income = '',
    this.spent = '',
    this.saved = '',
    this.incomeLabel = '',
    this.spentLabel = '',
    this.savedLabel = '',
    this.expenseAction = '',
    this.incomeAction = '',
    this.importAction = '',
  });

  /// The day [today] was worked out for, as `yyyy-MM-dd`. The widget shows
  /// [zero] instead once that day is over, so yesterday's spending is never
  /// passed off as today's.
  final String day;

  /// Today's spending, e.g. `NPR 1,250`.
  final String today;

  /// What "nothing spent" looks like, e.g. `NPR 0`.
  final String zero;

  /// The month line, e.g. `Kartik · NPR 12,300`.
  final String month;

  /// The caption above [today], e.g. `Spent today`.
  final String label;

  /// The text on the button, e.g. `+ Add`.
  final String add;

  /// The month widget: its heading, and this month's income, spending and
  /// what is left of the two, each with its caption.
  final String monthTitle;
  final String income;
  final String spent;
  final String saved;
  final String incomeLabel;
  final String spentLabel;
  final String savedLabel;

  /// The words on the action buttons: add an expense, add income, import.
  final String expenseAction;
  final String incomeAction;
  final String importAction;

  static String dayOf(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Only what was given: a text left empty falls back to the widget's own
  /// English wording.
  Map<String, String> toMap() => <String, String>{
    for (final entry in <String, String>{
      'day': day,
      'today': today,
      'zero': zero,
      'month': month,
      'label': label,
      'add': add,
      'monthTitle': monthTitle,
      'income': income,
      'spent': spent,
      'saved': saved,
      'incomeLabel': incomeLabel,
      'spentLabel': spentLabel,
      'savedLabel': savedLabel,
      'expenseAction': expenseAction,
      'incomeAction': incomeAction,
      'importAction': importAction,
    }.entries)
      if (entry.value.isNotEmpty) entry.key: entry.value,
  };

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetData && mapEquals(other.toMap(), toMap());

  @override
  int get hashCode => Object.hashAll(toMap().values);
}

/// The Android home-screen widgets and icon shortcuts, from the app's side.
///
/// A widget is drawn by the launcher and cannot run Dart, so the app pushes
/// the widgets their figures whenever they change and the native side stores
/// and shows them (android/.../KharchaWidget.kt). In the other direction a
/// widget button, or a shortcut from a long press on the app icon, opens the
/// app, and the tap arrives here as an action.
class HomeWidgetService {
  HomeWidgetService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const String channelName = 'com.nischalpandey.kharcha/home_widget';

  /// The widget's Add button.
  static const String addExpenseAction = 'add_expense';

  /// The page each action opens. An action that is not listed is ignored.
  static const Map<String, String> actionRoutes = <String, String>{
    addExpenseAction: RoutePaths.addExpense,
    'add_income': RoutePaths.addIncome,
    'import_statement': RoutePaths.statementImport,
    'scan_sms': RoutePaths.smsImport,
  };

  final MethodChannel _channel;
  final StreamController<String> _actions =
      StreamController<String>.broadcast();

  /// What was last sent, so an unchanged widget is not redrawn. Null when
  /// nothing has been sent, or the widget was cleared.
  HomeWidgetData? _sent;
  bool _cleared = false;

  /// Widget taps that arrive while the app is already running.
  Stream<String> get actions => _actions.stream;

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'action') return;
    final action = call.arguments;
    if (action is String) _actions.add(action);
  }

  /// The widget tap the app was opened with, if any. Returned once.
  Future<String?> takeInitialAction() async {
    try {
      return await _channel.invokeMethod<String>('takeInitialAction');
    } on MissingPluginException {
      // Not Android, or a test: there is no widget.
      return null;
    } catch (error) {
      debugPrint('Home widget: could not read the launch action ($error)');
      return null;
    }
  }

  /// Shows [data] on the widget. Does nothing when it already shows that.
  Future<void> update(HomeWidgetData data) async {
    if (data == _sent) return;
    _sent = data;
    _cleared = false;
    await _invoke('update', data.toMap());
  }

  /// Takes the figures off the widget, when nobody is signed in.
  Future<void> clear() async {
    if (_cleared) return;
    _sent = null;
    _cleared = true;
    await _invoke('clear');
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Not Android, or a test.
    } catch (error) {
      // The widget is a convenience; the app must never fail over it.
      debugPrint('Home widget: $method failed ($error)');
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _actions.close();
  }
}
