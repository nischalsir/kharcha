import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/router/route_paths.dart';
import 'core/theme/app_theme.dart';
import 'models/sync_models.dart';
import 'models/transaction_model.dart';
import 'providers/app_providers.dart';
import 'providers/ai_insight_provider.dart';
import 'providers/app_settings_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/budget_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/festival_provider.dart';
import 'providers/friend_provider.dart';
import 'providers/pasal_provider.dart';
import 'providers/push_provider.dart';
import 'providers/recurring_payment_provider.dart';
import 'providers/report_provider.dart';
import 'providers/transaction_provider.dart';
import 'screens/auth/introduction_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/mfa_challenge_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/budgets/budgets_screen.dart';
import 'screens/calculator/calculator_screen.dart';
import 'screens/festivals/festivals_screen.dart';
import 'screens/friends/friend_detail_screen.dart';
import 'screens/friends/friends_screen.dart';
import 'screens/pasal/add_pasal_credit_screen.dart';
import 'screens/pasal/add_pasal_screen.dart';
import 'screens/pasal/pasal_credit_history_screen.dart';
import 'screens/pasal/pasal_detail_screen.dart';
import 'screens/pasal/pasal_payment_history_screen.dart';
import 'screens/pasal/pasal_screen.dart';
import 'screens/payments/payments_screen.dart';
import 'screens/payments/statement_import_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/transactions/add_transaction_screen.dart';
import 'services/root_shell.dart';
import 'services/biometric_service.dart';
import 'services/cache_service.dart';
import 'services/nepali_date_service.dart';
import 'services/push_notification_service.dart';
import 'services/sync_service.dart';
import 'widgets/common/app_bottom_nav.dart';
import 'widgets/common/glass_background.dart';

import 'package:provider/single_child_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Must be registered before Firebase is initialised and before runApp: FCM
  // reads this at plugin registration time, and a background/terminated push
  // starts a headless isolate that only has this handler to draw with.
  FirebaseMessaging.onBackgroundMessage(
    kharchaFirebaseMessagingBackgroundHandler,
  );

  if (Env.hasSupabase) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
  }
  final env = await AppEnvironment.bootstrap();
  runApp(KharchaApp(env: env));
}

class KharchaApp extends StatelessWidget {
  const KharchaApp({super.key, required this.env});

  final AppEnvironment env;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        Provider<NepaliDateService>.value(value: env.dates),
        Provider<CacheService>.value(value: env.cache),
        ChangeNotifierProvider<SyncService>.value(value: env.sync),
        Provider<BiometricService>(create: (_) => BiometricService()),
        ChangeNotifierProvider<AuthProvider>(
          create: (context) =>
              AuthProvider(vault: context.read<BiometricService>())
                ..initialize(),
        ),
        ChangeNotifierProvider<AppSettingsProvider>(
          create: (_) => AppProviders.settings(env),
        ),
        ChangeNotifierProvider<TransactionProvider>(
          create: (_) => AppProviders.transactions(env),
        ),
        ChangeNotifierProvider<FriendProvider>(
          create: (_) => AppProviders.friends(env),
        ),
        ChangeNotifierProvider<BudgetProvider>(
          create: (_) => AppProviders.budgets(env),
        ),
        ChangeNotifierProvider<RecurringPaymentProvider>(
          create: (_) => AppProviders.recurring(env),
        ),
        ChangeNotifierProvider<PasalProvider>(
          create: (_) => AppProviders.pasal(env),
        ),
        ChangeNotifierProvider<FestivalProvider>(
          create: (_) => AppProviders.festivals(env),
        ),
        ChangeNotifierProvider<DashboardProvider>(
          create: (_) => AppProviders.dashboard(env),
        ),
        ChangeNotifierProvider<ReportProvider>(
          create: (_) => AppProviders.reports(env),
        ),
        ChangeNotifierProvider<AiInsightProvider>(
          create: (_) => AppProviders.aiInsight(env),
        ),
        ChangeNotifierProvider<PushProvider>(
          create: (_) => PushProvider()..initialize(),
        ),
      ],
      child: Consumer<AppSettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'Kharcha',
            debugShowCheckedModeBanner: false,
            themeMode: settings.themeMode,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            navigatorObservers: <NavigatorObserver>[AppNavRouteObserver()],
            // Screens pushed as routes (Calendar/Festivals, Settings, Budgets…)
            // are not always wrapped in their own Scaffold, but widgets such as
            // InkWell/ListTile require a Material ancestor. This transparent
            // Material sits above the Navigator so every route has one.
            builder: (context, child) => Material(
              type: MaterialType.transparency,
              child: child ?? const SizedBox.shrink(),
            ),
            onGenerateRoute: _generateRoute,
            home: const _AuthWrapper(),
          );
        },
      ),
    );
  }

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    final String? name = settings.name;
    if (name == null) return null;
    // Detail routes are addressed by id through `arguments`.
    final String? id = settings.arguments is String
        ? settings.arguments! as String
        : null;

    final Widget? page = switch (name) {
      RoutePaths.introduction => const IntroductionScreen(),
      RoutePaths.login => const LoginScreen(),
      RoutePaths.signup => const SignupScreen(),
      RoutePaths.home => const RootShell(),
      RoutePaths.payments => const PaymentsScreen(),
      RoutePaths.statementImport => const StatementImportScreen(),
      RoutePaths.friends => const FriendsScreen(),
      RoutePaths.friendDetail =>
        id == null ? null : FriendDetailScreen(friendId: id),
      RoutePaths.pasal => const PasalScreen(),
      RoutePaths.addPasal => const AddPasalScreen(),
      RoutePaths.pasalDetail =>
        id == null ? null : PasalDetailScreen(pasalId: id),
      RoutePaths.addPasalCredit =>
        id == null ? null : AddPasalCreditScreen(pasalId: id),
      RoutePaths.pasalCreditHistory =>
        id == null ? null : PasalCreditHistoryScreen(pasalId: id),
      RoutePaths.pasalPaymentHistory =>
        id == null ? null : PasalPaymentHistoryScreen(pasalId: id),
      RoutePaths.budgets => const BudgetsScreen(),
      RoutePaths.reports => const ReportsScreen(),
      RoutePaths.calculator => const CalculatorScreen(),
      RoutePaths.festivals => const FestivalsScreen(),
      RoutePaths.settings => const SettingsScreen(),
      RoutePaths.addExpense => const AddTransactionScreen(
        initialType: TransactionType.expense,
      ),
      RoutePaths.addIncome => const AddTransactionScreen(
        initialType: TransactionType.income,
      ),
      _ => null,
    };
    if (page == null) return null;
    return MaterialPageRoute<dynamic>(builder: (_) => page, settings: settings);
  }
}

class _AuthWrapper extends StatefulWidget {
  const _AuthWrapper();

  @override
  State<_AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<_AuthWrapper>
    with WidgetsBindingObserver {
  AuthProvider? _auth;
  VoidCallback? _registrationListener;
  Future<void> Function()? _signOutCleanup;
  bool _listening = false;

  /// The account whose data the cache is known to hold. The app shell is only
  /// shown for this account, so a screen can never be built from whatever the
  /// previous account left on the device.
  String? _readyUserId;

  /// The account currently being prepared, so repeated auth events for one
  /// sign-in start the work once.
  String? _preparingUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listening) return;
    _listening = true;

    // The auth provider is created lazily above, so it is only safe to read
    // once the element tree is being built.
    final auth = context.read<AuthProvider>();
    _auth = auth;
    _installPushWiring(auth);
  }

  /// Keeps the server's token registry in step with the signed-in account and
  /// routes notification taps.
  ///
  /// Both are attached here rather than inside [PushProvider] because taps need
  /// a navigator, and registration needs the current user id, which only this
  /// part of the tree knows about.
  void _installPushWiring(AuthProvider auth) {
    final push = context.read<PushProvider>();
    final sync = context.read<SyncService>();

    // Installed once: a pending tap from a cold start is delivered as soon as a
    // handler exists, so nothing is lost by being early or late here.
    if (push.onTap == null) {
      push.setTapHandler(
        (message) => _openPushRoute(auth, message.route, message.routeArgs),
      );
    }

    void syncRegistration() {
      unawaited(
        push.sync(authenticated: auth.isAuthenticated, userId: auth.userId),
      );
      final userId = auth.userId;
      if (!auth.isAuthenticated || userId == null) {
        _readyUserId = null;
        return;
      }
      if (_readyUserId == userId || _preparingUserId == userId) return;
      // A different account than the one on screen: nothing of the old one
      // may be shown while the new one is being set up.
      _readyUserId = null;
      _preparingUserId = userId;
      unawaited(_prepareAccount(auth, sync, userId));
    }

    _registrationListener = syncRegistration;
    auth.addListener(syncRegistration);
    // Runs inside signOut, while the session is still valid. Without this the
    // token delete happens after the JWT is gone, RLS rejects it, and the
    // previous account keeps sending this device its notifications.
    // Queued writes are pushed first, for the same reason: after sign-out
    // they could only ever be uploaded by whichever account signs in next.
    final biometric = context.read<BiometricService>();
    _signOutCleanup = () async {
      // The account signing out is the one to offer on the sign-in form next,
      // whoever else has used this phone. Read here, while it is still known.
      final email = auth.userEmail;
      if (email != null && email.isNotEmpty) {
        await biometric.setRememberedEmail(
          await biometric.rememberMe() ? email : null,
        );
      }
      await sync.flushBeforeSignOut();
      await push.unregisterForSignOut();
    };
    auth.addSignOutCleanup(_signOutCleanup!);
    // Covers the already-signed-in case at startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      syncRegistration();
      final dates = context.read<NepaliDateService>();
      context.read<FestivalProvider>().checkFestivalReminders(
        devanagari: dates.devanagari,
      );
    });
  }

  /// Ties the offline cache to [userId] and, when the device last held another
  /// account's data, fetches this account's own before the app is shown.
  Future<void> _prepareAccount(
    AuthProvider auth,
    SyncService sync,
    String userId,
  ) async {
    final settings = context.read<AppSettingsProvider>();
    final insight = context.read<AiInsightProvider>();
    try {
      final adoption = await sync.adoptUser(userId);
      if (adoption == AccountAdoption.switched) {
        await insight.resetForAccount();
      }
      if (adoption != AccountAdoption.unchanged) {
        // Bounded: a slow network must not hold the user on a spinner, and the
        // sync carries on in the background either way.
        try {
          await sync.refresh().timeout(const Duration(seconds: 12));
        } catch (_) {
          // Offline or slow; whatever arrived is shown and the rest follows.
        }
      }
      if (adoption == AccountAdoption.switched && auth.userId == userId) {
        await settings.ensureAccountDefaults(
          fetched: sync.status == SyncStatus.synced,
        );
      }
    } catch (error) {
      debugPrint('Auth: could not prepare the account ($error)');
    } finally {
      if (_preparingUserId == userId) _preparingUserId = null;
      // Signed out, or someone else signed in, while this was running: this
      // result is for an account that is no longer the active one.
      if (mounted && auth.isAuthenticated && auth.userId == userId) {
        setState(() => _readyUserId = userId);
      }
    }
  }

  /// Opens a route named by a push, ignoring anything this app cannot resolve.
  Future<void> _openPushRoute(
    AuthProvider auth,
    String? route,
    String? args,
  ) async {
    if (!mounted) return;
    if (!RoutePaths.isKnown(route)) return;
    // Every push target is a private screen, and the auth wrapper only reaches
    // the login screen on its own once this runs. Navigating for a signed-out
    // user would put that data on screen, so the tap is dropped and login is
    // already what is being shown.
    if (!auth.isAuthenticated || auth.mfaPending) return;
    if (_readyUserId != auth.userId) return;

    final navigator = Navigator.of(context);
    // A tap while another screen is up is the common case, not an error: the
    // notification was raised independently of where the user had wandered to.
    // Unwind to the root so the target screen is built on a clean stack instead
    // of landing on top of an unrelated detail screen.
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
    if (!mounted) return;
    await navigator.pushNamed(route!, arguments: args);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final auth = _auth;
    final listener = _registrationListener;
    if (auth != null && listener != null) auth.removeListener(listener);
    final cleanup = _signOutCleanup;
    if (auth != null && cleanup != null) auth.removeSignOutCleanup(cleanup);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // "Remember me" off means the session must not survive leaving the app, so
    // the next cold start lands on the login screen again.
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached &&
        state != AppLifecycleState.hidden) {
      return;
    }
    final BiometricService biometric = context.read<BiometricService>();
    final AuthProvider auth = context.read<AuthProvider>();
    biometric
        .rememberMe()
        .then((remember) {
          if (remember) return;
          if (!auth.isAuthenticated) return;
          auth.signOut().catchError((_) {
            // Nothing to sign out of.
          });
        })
        .catchError((_) {
          // Secure storage unavailable; leave the session untouched.
        });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, AppSettingsProvider>(
      builder: (context, authProvider, settingsProvider, _) {
        // Show loading only until the persisted session has been restored —
        // never during an interactive sign-in, or the form being filled in
        // would be torn down underneath the user.
        if (authProvider.isInitializing || !settingsProvider.isReady) {
          return GlassBackground(child: const _BootLoading());
        }

        // Show introduction if not seen
        if (!settingsProvider.hasSeenIntroduction) {
          return const IntroductionScreen();
        }

        // Show login if not authenticated
        if (!authProvider.isAuthenticated) {
          return const LoginScreen();
        }

        // Password sign-in succeeded but the account has an authenticator
        // factor: require the 6-digit code before opening the app.
        if (authProvider.mfaPending) {
          return const MfaChallengeScreen();
        }

        // Signed in, but the cache has not been confirmed as this account's
        // yet. Showing the shell now would build it from the previous
        // account's data.
        if (_readyUserId != authProvider.userId) {
          return GlassBackground(child: const _BootLoading());
        }

        // Keyed by account, so switching rebuilds every screen from scratch
        // instead of reusing state the previous account left in them.
        return GlassBackground(
          child: RootShell(key: ValueKey<String?>(authProvider.userId)),
        );
      },
    );
  }
}

class _BootLoading extends StatelessWidget {
  const _BootLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      ),
    );
  }
}
