/// Every named route the app can resolve.
///
/// Each constant here must have a case in `main.dart`'s `_generateRoute`, and
/// a screen that exists — an unresolvable name is a runtime crash, not a no-op.
/// Routes carrying an id read it from `RouteSettings.arguments` as a `String`.
class RoutePaths {
  const RoutePaths._();

  // Auth routes
  static const String introduction = '/intro';
  static const String login = '/login';
  static const String signup = '/signup';

  // Main app routes
  static const String home = '/';
  static const String payments = '/payments';

  /// Import transactions from an uploaded bank statement PDF.
  static const String statementImport = '/payments/import';

  static const String friends = '/friends';

  /// Requires `settings.arguments` to be a friend id.
  static const String friendDetail = '/friends/detail';

  static const String pasal = '/pasal';
  static const String addPasal = '/pasal/add';

  /// Requires `settings.arguments` to be a pasal id.
  static const String pasalDetail = '/pasal/detail';

  /// Requires `settings.arguments` to be a pasal id.
  static const String addPasalCredit = '/pasal/credit/add';

  /// Requires `settings.arguments` to be a pasal id.
  static const String pasalCreditHistory = '/pasal/credit/history';

  /// Requires `settings.arguments` to be a pasal id.
  static const String pasalPaymentHistory = '/pasal/payment/history';

  static const String budgets = '/budgets';
  static const String reports = '/reports';
  static const String calculator = '/calculator';
  static const String festivals = '/festivals';
  static const String settings = '/settings';

  /// Settings → About Kharcha: version, update status and what's new.
  static const String about = '/settings/about';

  static const String addExpense = '/transactions/expense/add';
  static const String addIncome = '/transactions/income/add';

  /// Every route name above, for validating a route that arrived from outside
  /// the app.
  ///
  /// A notification's `route` is attacker-influenced data: it comes from a push
  /// payload, and a push payload can be forged by anyone holding the server key.
  /// Navigating to a name with no case in `_generateRoute` is a runtime crash
  /// rather than a no-op, so a route is only followed when it is in this set.
  static const Set<String> all = <String>{
    introduction,
    login,
    signup,
    home,
    payments,
    statementImport,
    friends,
    friendDetail,
    pasal,
    addPasal,
    pasalDetail,
    addPasalCredit,
    pasalCreditHistory,
    pasalPaymentHistory,
    budgets,
    reports,
    calculator,
    festivals,
    settings,
    about,
    addExpense,
    addIncome,
  };

  /// Whether [route] is one this app can actually open.
  static bool isKnown(String? route) => route != null && all.contains(route);
}
