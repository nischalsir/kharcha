import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/router/route_paths.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/currency_formatter.dart';
import 'models/push_message.dart';
import 'models/sync_models.dart';
import 'models/transaction_model.dart';
import 'providers/app_providers.dart';
import 'providers/ai_insight_provider.dart';
import 'providers/app_settings_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/budget_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/festival_budget_provider.dart';
import 'providers/festival_provider.dart';
import 'providers/friend_provider.dart';
import 'providers/household_provider.dart';
import 'providers/loan_provider.dart';
import 'providers/pasal_provider.dart';
import 'providers/push_provider.dart';
import 'providers/recurring_payment_provider.dart';
import 'providers/report_provider.dart';
import 'providers/savings_goal_provider.dart';
import 'providers/transaction_provider.dart';
import 'providers/update_provider.dart';
import 'providers/wallet_provider.dart';
import 'screens/auth/introduction_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/mfa_challenge_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/budgets/budgets_screen.dart';
import 'screens/calculator/calculator_screen.dart';
import 'screens/festivals/festivals_screen.dart';
import 'screens/friends/friend_detail_screen.dart';
import 'screens/friends/friends_screen.dart';
import 'screens/goals/goals_screen.dart';
import 'screens/household/household_screen.dart';
import 'screens/loans/loans_screen.dart';
import 'screens/pasal/add_pasal_credit_screen.dart';
import 'screens/pasal/add_pasal_screen.dart';
import 'screens/pasal/pasal_credit_history_screen.dart';
import 'screens/pasal/pasal_detail_screen.dart';
import 'screens/pasal/pasal_payment_history_screen.dart';
import 'screens/pasal/pasal_screen.dart';
import 'screens/payments/payments_screen.dart';
import 'screens/payments/sms_import_screen.dart';
import 'screens/payments/statement_import_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/settings/backup_restore_screen.dart';
import 'screens/settings/help_support_screen.dart';
import 'screens/settings/profile_edit_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/settings/version_screen.dart';
import 'screens/transactions/add_transaction_screen.dart';
import 'screens/wallets/wallets_screen.dart';
import 'services/root_shell.dart';
import 'services/biometric_service.dart';
import 'services/cache_service.dart';
import 'services/account_avatar_cache.dart';
import 'services/app_images.dart';
import 'services/flamey_controller.dart';
import 'services/google_account.dart';
import 'services/google_drive_backup_service.dart';
import 'services/home_widget_service.dart';
import 'services/incoming_file_service.dart';
import 'services/image_preload.dart';
import 'services/nepali_date_service.dart';
import 'services/pasal_image_store.dart';
import 'services/push_notification_service.dart';
import 'services/sync_service.dart';
import 'services/update_service.dart';
import 'widgets/common/app_bottom_nav.dart';
import 'widgets/common/account_transition.dart';
import 'widgets/common/glass_background.dart';
import 'widgets/common/update_dialog.dart';

import 'package:provider/single_child_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Every screen is laid out for portrait. Declared here as well as in the
  // Android manifest, which is what stops the system offering to rotate when
  // the phone is tilted.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

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
  AppImages.enableDiskCache();
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
        Provider<AccountAvatarCache>(create: (_) => AccountAvatarCache()),
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
        ChangeNotifierProvider<SavingsGoalProvider>(
          create: (_) => AppProviders.savingsGoals(env),
        ),
        ChangeNotifierProvider<WalletProvider>(
          create: (_) => AppProviders.wallets(env),
        ),
        ChangeNotifierProvider<FestivalBudgetProvider>(
          create: (_) => AppProviders.festivalBudgets(env),
        ),
        ChangeNotifierProvider<LoanProvider>(
          create: (_) => AppProviders.loans(env),
        ),
        ChangeNotifierProvider<HouseholdProvider>(
          create: (_) => AppProviders.household(env),
        ),
        ChangeNotifierProvider<DashboardProvider>(
          create: (_) => AppProviders.dashboard(env),
        ),
        ChangeNotifierProvider<ReportProvider>(
          create: (_) => AppProviders.reports(env),
        ),
        // Flamey's state machine. Above the AI provider, which tells it
        // what the current suggestion looks like.
        ChangeNotifierProvider<FlameyController>(
          create: (_) => FlameyController(),
        ),
        Provider<IncomingFileService>(
          create: (_) => IncomingFileService(),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<HomeWidgetService>(
          create: (_) => HomeWidgetService(),
          dispose: (_, service) => service.dispose(),
        ),
        ChangeNotifierProvider<AiInsightProvider>(
          create: (context) => AppProviders.aiInsight(
            env,
            flamey: context.read<FlameyController>(),
          ),
        ),
        ChangeNotifierProvider<PushProvider>(
          create: (_) => PushProvider()..initialize(),
        ),
        ChangeNotifierProvider<UpdateProvider>(
          create: (_) => UpdateProvider(onUpdateFound: _notifyUpdate),
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
              // Above the navigator, so the signing in / out screen covers
              // every route and dialog, not just the page underneath.
              child: AccountTransitionOverlay(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
            onGenerateRoute: _generateRoute,
            home: const _AuthWrapper(),
          );
        },
      ),
    );
  }

  /// Stable id, so the update notification replaces itself instead of piling
  /// up one per launch.
  static const int _updateNotificationId = 0x5550;

  /// Posts the "update available" notification through the same renderer and
  /// channels as every other Kharcha notification. Tapping it opens About.
  static Future<void> _notifyUpdate(UpdateInfo update) {
    return PushNotificationService.render(
      PushMessage(
        category: 'app_update',
        title: 'Update available',
        body:
            'Kharcha ${update.version} is ready. Tap to see what’s new and '
            'download it.',
        data: const <String, String>{'route': RoutePaths.about},
      ),
      id: _updateNotificationId,
    );
  }

  /// The screen for a named route, or null when [name] is not a route this
  /// app has (or a detail route came without its id).
  ///
  /// Every name in `RoutePaths.all` must have a case here; a test checks it,
  /// so a row or a notification can never lead to a route that crashes.
  @visibleForTesting
  static Widget? pageFor(String name, String? id) => switch (name) {
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
    RoutePaths.goals => const GoalsScreen(),
    RoutePaths.wallets => const WalletsScreen(),
    RoutePaths.loans => const LoansScreen(),
    RoutePaths.household => const HouseholdScreen(),
    RoutePaths.smsImport => const SmsImportScreen(),
    RoutePaths.reports => const ReportsScreen(),
    RoutePaths.calculator => const CalculatorScreen(),
    RoutePaths.festivals => const FestivalsScreen(),
    RoutePaths.settings => const SettingsScreen(),
    RoutePaths.profile => const ProfileEditScreen(),
    RoutePaths.about => const VersionScreen(),
    RoutePaths.backup => const BackupRestoreScreen(),
    RoutePaths.help => const HelpSupportScreen(),
    RoutePaths.addExpense => const AddTransactionScreen(
      initialType: TransactionType.expense,
    ),
    RoutePaths.addIncome => const AddTransactionScreen(
      initialType: TransactionType.income,
    ),
    _ => null,
  };

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    final String? name = settings.name;
    if (name == null) return null;
    // Detail routes are addressed by id through `arguments`.
    final String? id = settings.arguments is String
        ? settings.arguments! as String
        : null;

    final Widget? page = pageFor(name, id);
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

  /// Set once this launch has shown the signed-out state. From then on an
  /// account being prepared is one the user just signed in to, and is
  /// announced by name; before that it is the session restored at startup.
  bool _signedOutSeen = false;

  UpdateProvider? _updates;

  /// A statement another app shared into Kharcha, waiting for an account to
  /// be signed in and ready before it is opened in the importer.
  IncomingFile? _pendingFile;
  StreamSubscription<IncomingFile>? _incomingSub;

  /// The home-screen widget, the figures it shows and the settings that
  /// decide how they are written.
  HomeWidgetService? _homeWidget;
  DashboardProvider? _dashboard;
  AppSettingsProvider? _settings;
  StreamSubscription<String>? _widgetSub;

  /// The page the widget's button asked for, waiting like [_pendingFile] for
  /// an account to be signed in and ready.
  String? _pendingShortcut;

  /// When the app last went to the background, to greet a return.
  DateTime? _leftAt;

  /// Away at least this long counts as "back after some time".
  static const Duration _awayThreshold = Duration(minutes: 30);

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
    _installUpdateCheck(auth);
    _installIncomingFiles();
    _installHomeWidget(auth);
    // After the first frame, so fetching pictures never delays the app
    // appearing.
    WidgetsBinding.instance.addPostFrameCallback((_) => _preloadImages());
  }

  /// Listens for statements shared into the app: the one it may have been
  /// opened with, and any that arrive while it is running.
  void _installIncomingFiles() {
    final files = context.read<IncomingFileService>();
    _incomingSub = files.files.listen(_receiveFile);
    files.takeInitial().then((file) {
      if (file != null) _receiveFile(file);
    });
  }

  void _receiveFile(IncomingFile file) {
    if (!mounted) return;
    // A newer share replaces one that was never opened.
    final waiting = _pendingFile;
    if (waiting != null) {
      unawaited(context.read<IncomingFileService>().discard(waiting));
    }
    _pendingFile = file;
    _openPendingFile();
  }

  /// Opens the shared statement in the importer, once someone is signed in
  /// and their own data is what the app is showing. Until then the file
  /// waits: a statement must never be imported into whichever account
  /// happens to be on screen, or into none.
  void _openPendingFile() {
    final file = _pendingFile;
    final auth = _auth;
    if (file == null || auth == null || !mounted) return;
    if (!auth.isAuthenticated || auth.mfaPending) return;
    if (_readyUserId != auth.userId) return;
    _pendingFile = null;
    final files = context.read<IncomingFileService>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      // On top of the home screen, not of whatever was open before.
      if (navigator.canPop()) navigator.popUntil((route) => route.isFirst);
      navigator.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: RoutePaths.statementImport),
          builder: (_) =>
              StatementImportScreen(incoming: file, incomingFiles: files),
        ),
      );
    });
  }

  /// Keeps the home-screen widget showing this account's spending, and
  /// listens for its Add button.
  void _installHomeWidget(AuthProvider auth) {
    final service = context.read<HomeWidgetService>();
    _homeWidget = service;
    _widgetSub = service.actions.listen(_receiveWidgetAction);
    service.takeInitialAction().then((action) {
      if (action != null) _receiveWidgetAction(action);
    });
    _dashboard = context.read<DashboardProvider>()
      ..addListener(_syncHomeWidget);
    // The currency and the language are part of what the widget shows.
    _settings = context.read<AppSettingsProvider>()
      ..addListener(_syncHomeWidget);
    auth.addListener(_syncHomeWidget);
  }

  void _receiveWidgetAction(String action) {
    final route = HomeWidgetService.actionRoutes[action];
    if (!mounted || route == null) return;
    _pendingShortcut = route;
    _openPendingShortcut();
  }

  /// Opens the page the widget asked for, under the same conditions as a
  /// shared statement: only for a signed-in account whose data is on screen.
  void _openPendingShortcut() {
    final route = _pendingShortcut;
    final auth = _auth;
    if (route == null || auth == null || !mounted) return;
    if (!auth.isAuthenticated || auth.mfaPending) return;
    if (_readyUserId != auth.userId) return;
    _pendingShortcut = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.popUntil((route) => route.isFirst);
      navigator.pushNamed(route);
    });
  }

  /// Sends the widget what it should show now. Nothing of an account is put
  /// on the home screen until that account is the one the app is showing,
  /// and it is taken off again when it signs out.
  void _syncHomeWidget() {
    final auth = _auth;
    final service = _homeWidget;
    final dashboard = _dashboard;
    if (!mounted || auth == null || service == null || dashboard == null) {
      return;
    }
    if (!auth.isAuthenticated) {
      if (!auth.isInitializing) unawaited(service.clear());
      return;
    }
    if (auth.mfaPending || _readyUserId != auth.userId) return;
    final nepali = context.read<NepaliDateService>().devanagari;
    final data = dashboard.data;
    final month = CurrencyFormatter.format(data.totalExpense);
    String words(String en, String ne) => nepali ? ne : en;
    unawaited(
      service.update(
        HomeWidgetData(
          day: HomeWidgetData.dayOf(DateTime.now()),
          today: CurrencyFormatter.format(data.todayExpense),
          zero: CurrencyFormatter.format(0),
          month: nepali ? 'यो महिना · $month' : 'This month · $month',
          label: nepali ? 'आजको खर्च' : 'Spent today',
          add: nepali ? '+ थप्नुहोस्' : '+ Add',
          monthTitle: words('This month', 'यो महिना'),
          income: CurrencyFormatter.format(data.totalIncome),
          spent: month,
          saved: CurrencyFormatter.format(data.netSavings),
          incomeLabel: words('Income', 'आम्दानी'),
          spentLabel: words('Spent', 'खर्च'),
          savedLabel: words('Saved', 'बचत'),
          expenseAction: words('Add expense', 'खर्च थप्नुहोस्'),
          incomeAction: words('Add income', 'आम्दानी थप्नुहोस्'),
          importAction: words('Import', 'आयात'),
        ),
      ),
    );
  }

  /// Fetches the app's pictures into its on-disk cache, so the pages that
  /// show them open instantly from then on. Runs when the app opens and
  /// again once an account is ready; what is already stored is skipped.
  void _preloadImages() {
    if (!mounted) return;
    final media = MediaQuery.maybeOf(context);
    final auth = _auth;
    if (media == null || auth == null) return;
    ImagePreload.run(
      screenWidth: media.size.width,
      devicePixelRatio: media.devicePixelRatio,
      signedIn: auth.isAuthenticated,
    );
  }

  /// Starts the one update check of this launch and offers the update prompt
  /// once the app has settled on a screen.
  ///
  /// The check itself touches nothing but the update provider. The prompt
  /// waits for a quiet moment - see [_offerUpdate] - so it can never sit on
  /// top of a sign-in, the code screen or an account being loaded.
  void _installUpdateCheck(AuthProvider auth) {
    final updates = context.read<UpdateProvider>();
    _updates = updates;
    updates.addListener(_scheduleUpdateOffer);
    auth.addListener(_scheduleUpdateOffer);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(updates.checkOnLaunch());
    });
  }

  void _scheduleUpdateOffer() {
    if (!mounted || _updates?.promptPending != true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerUpdate());
  }

  void _offerUpdate() {
    if (!mounted) return;
    final updates = _updates;
    final auth = _auth;
    if (updates == null || auth == null || !updates.promptPending) return;
    // Not while something is in flight: restoring the session, signing in,
    // waiting for an authenticator code, or loading an account's data.
    if (auth.isInitializing || auth.isLoading || auth.mfaPending) return;
    if (auth.isAuthenticated && _readyUserId != auth.userId) return;
    // Not over another route or dialog (signup, the account chooser, ...).
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (!context.read<AppSettingsProvider>().hasSeenIntroduction) return;
    if (!updates.takePrompt()) return;
    unawaited(showUpdateDialog(context));
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
        if (!auth.isInitializing) _signedOutSeen = true;
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
    final avatars = context.read<AccountAvatarCache>();
    _signOutCleanup = () async {
      // The account signing out is the one to offer on the sign-in form next,
      // whoever else has used this phone. Read here, while it is still known.
      final email = auth.userEmail;
      if (email != null && email.isNotEmpty) {
        await biometric.setRememberedEmail(
          await biometric.rememberMe() ? email : null,
        );
      }
      // Save this account's picture for the sign-in screens (the fingerprint
      // account chooser and "Signing in as"), while it can still be fetched.
      // Only for accounts this device is asked to remember, and bounded so
      // it cannot hold up signing out.
      final keepsAccount =
          email != null &&
          (await biometric.rememberMe() || await biometric.isEnabledFor(email));
      if (email != null && !keepsAccount) {
        await avatars.remove(email);
      }
      if (email != null && keepsAccount) {
        try {
          await avatars
              .capture(email, await auth.signedAvatarUrl())
              .timeout(const Duration(seconds: 6));
        } catch (_) {
          // Slow or offline: the chooser shows the account's initial.
        }
      }
      await sync.flushBeforeSignOut();
      await push.unregisterForSignOut();
      // The Google account connected for Drive backup belongs to the account
      // signing out. Forgetting it here means whoever signs in next is never
      // silently connected to someone else's Drive.
      // Only when this account ever connected one: nothing is asked of
      // Google otherwise.
      final leaving = auth.userId;
      if (leaving != null &&
          await const PrefsDriveLinkStore().linkedEmail(leaving) != null) {
        await GoogleAccount.signOut().timeout(
          const Duration(seconds: 4),
          onTimeout: () {},
        );
      }
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
        PasalImageStore.clearCache();
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
      // After the account's own rows have arrived, so a category it already
      // has on the server is recognised rather than copied.
      if (auth.userId == userId) await settings.claimDefaultIds(userId);
    } catch (error) {
      debugPrint('Auth: could not prepare the account ($error)');
    } finally {
      if (_preparingUserId == userId) _preparingUserId = null;
      // Signed out, or someone else signed in, while this was running: this
      // result is for an account that is no longer the active one.
      if (mounted && auth.isAuthenticated && auth.userId == userId) {
        setState(() => _readyUserId = userId);
        _scheduleUpdateOffer();
        _preloadImages();
        _openPendingFile();
        _openPendingShortcut();
        _syncHomeWidget();
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
    // The About page shows nothing private, and an update matters whether or
    // not anyone is signed in.
    if (route == RoutePaths.about) {
      final navigator = Navigator.of(context);
      // Already there (a second tap): do not stack another copy.
      var onAbout = false;
      navigator.popUntil((current) {
        onAbout = current.settings.name == RoutePaths.about;
        return true;
      });
      if (!onAbout) await navigator.pushNamed(route!);
      return;
    }
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
    _incomingSub?.cancel();
    _widgetSub?.cancel();
    _dashboard?.removeListener(_syncHomeWidget);
    _settings?.removeListener(_syncHomeWidget);
    _auth?.removeListener(_syncHomeWidget);
    final auth = _auth;
    final listener = _registrationListener;
    if (auth != null && listener != null) auth.removeListener(listener);
    final cleanup = _signOutCleanup;
    if (auth != null && cleanup != null) auth.removeSignOutCleanup(cleanup);
    _updates?.removeListener(_scheduleUpdateOffer);
    auth?.removeListener(_scheduleUpdateOffer);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final flamey = context.read<FlameyController>();
    if (state == AppLifecycleState.resumed) {
      // Back in front: Flamey's idle loop may run again, and a new time
      // window may have begun while the app was away.
      flamey.setForeground(true);
      final left = _leftAt;
      _leftAt = null;
      if (left != null &&
          DateTime.now().difference(left) >= _awayThreshold &&
          (_auth?.isAuthenticated ?? false)) {
        flamey.send(FlameyEvent.returned);
      }
      context.read<AiInsightProvider>().onAppResumed();
      _openPendingFile();
      _openPendingShortcut();
      // A new day may have begun while the app was away: "today" is worked
      // out again, which also puts the widget right.
      _dashboard?.refreshFromCache();
      return;
    }
    // "Remember me" off means the session must not survive leaving the app, so
    // the next cold start lands on the login screen again.
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached &&
        state != AppLifecycleState.hidden) {
      return;
    }
    // Nobody can see Flamey now: no timer needs to run.
    flamey.setForeground(false);
    _leftAt ??= DateTime.now();
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
          return _signedOutSeen
              ? AccountTransitionView.signingIn(email: authProvider.userEmail)
              : GlassBackground(child: const _BootLoading());
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
