import 'package:flutter/foundation.dart';

import '../repositories/budget_repository.dart';
import '../repositories/festival_budget_repository.dart';
import '../repositories/friend_repository.dart';
import '../repositories/household_repository.dart';
import '../repositories/loan_repository.dart';
import '../repositories/pasal_repository.dart';
import '../repositories/recurring_payment_repository.dart';
import '../repositories/savings_goal_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/transaction_repository.dart';
import '../services/ai_insight_service.dart';
import '../services/ai_mood_service.dart';
import '../services/cache_service.dart';
import '../services/festival_service.dart';
import '../services/financial_summary_service.dart';
import '../services/flamey_controller.dart';
import '../services/nepali_date_service.dart';
import '../services/reaction_notifier.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import '../services/weather_service.dart';
import 'ai_insight_provider.dart';
import 'app_settings_provider.dart';
import 'budget_provider.dart';
import 'dashboard_provider.dart';
import 'festival_budget_provider.dart';
import 'festival_provider.dart';
import 'friend_provider.dart';
import 'household_provider.dart';
import 'loan_provider.dart';
import 'pasal_provider.dart';
import 'recurring_payment_provider.dart';
import 'report_provider.dart';
import 'savings_goal_provider.dart';
import 'transaction_provider.dart';
import 'wallet_provider.dart';

@immutable
class AppEnvironment {
  const AppEnvironment({
    required this.cache,
    required this.sync,
    required this.dates,
    required this.settingsRepository,
    required this.transactionRepository,
    required this.friendRepository,
    required this.budgetRepository,
    required this.recurringRepository,
    required this.pasalRepository,
    required this.festivalService,
    required this.savingsGoalRepository,
    required this.festivalBudgetRepository,
    required this.loanRepository,
    required this.householdRepository,
  });

  final CacheService cache;
  final SyncService sync;
  final NepaliDateService dates;
  final SettingsRepository settingsRepository;
  final TransactionRepository transactionRepository;
  final FriendRepository friendRepository;
  final BudgetRepository budgetRepository;
  final RecurringPaymentRepository recurringRepository;
  final PasalRepository pasalRepository;
  final FestivalService festivalService;
  final SavingsGoalRepository savingsGoalRepository;
  final FestivalBudgetRepository festivalBudgetRepository;
  final LoanRepository loanRepository;
  final HouseholdRepository householdRepository;

  static Future<AppEnvironment> bootstrap() async {
    final cache = await CacheService.create();
    final remote = SupabaseService();
    final sync = SyncService(cache: cache, remote: remote);
    final dates = NepaliDateService();
    final transactionRepository = TransactionRepository(cache, sync);
    final recurringRepository = RecurringPaymentRepository(
      cache,
      sync,
      transactionRepository,
      dates,
    );
    return AppEnvironment(
      cache: cache,
      sync: sync,
      dates: dates,
      settingsRepository: SettingsRepository(cache, sync),
      transactionRepository: transactionRepository,
      friendRepository: FriendRepository(cache, sync),
      budgetRepository: BudgetRepository(cache, sync),
      recurringRepository: recurringRepository,
      loanRepository: LoanRepository(
        cache,
        sync,
        recurringRepository,
        transactionRepository,
      ),
      householdRepository: HouseholdRepository(cache, sync),
      pasalRepository: PasalRepository(cache, sync),
      festivalService: FestivalService(dates),
      savingsGoalRepository: SavingsGoalRepository(cache, sync),
      festivalBudgetRepository: FestivalBudgetRepository(cache, sync),
    );
  }
}

class AppProviders {
  const AppProviders._();

  static AppSettingsProvider settings(AppEnvironment env) {
    return AppSettingsProvider(
      cache: env.cache,
      sync: env.sync,
      repository: env.settingsRepository,
      dates: env.dates,
    );
  }

  static TransactionProvider transactions(AppEnvironment env) {
    return TransactionProvider(
      cache: env.cache,
      repository: env.transactionRepository,
    );
  }

  static FriendProvider friends(AppEnvironment env) {
    return FriendProvider(cache: env.cache, repository: env.friendRepository);
  }

  static BudgetProvider budgets(AppEnvironment env) {
    return BudgetProvider(
      cache: env.cache,
      repository: env.budgetRepository,
      transactions: env.transactionRepository,
      dates: env.dates,
    );
  }

  static RecurringPaymentProvider recurring(AppEnvironment env) {
    return RecurringPaymentProvider(
      cache: env.cache,
      repository: env.recurringRepository,
    );
  }

  static PasalProvider pasal(AppEnvironment env) {
    return PasalProvider(
      cache: env.cache,
      repository: env.pasalRepository,
      dates: env.dates,
    );
  }

  static FestivalProvider festivals(AppEnvironment env) {
    return FestivalProvider(service: env.festivalService, dates: env.dates);
  }

  static SavingsGoalProvider savingsGoals(AppEnvironment env) {
    return SavingsGoalProvider(
      cache: env.cache,
      repository: env.savingsGoalRepository,
    );
  }

  static WalletProvider wallets(AppEnvironment env) {
    return WalletProvider(
      cache: env.cache,
      settings: env.settingsRepository,
      transactions: env.transactionRepository,
    );
  }

  static FestivalBudgetProvider festivalBudgets(AppEnvironment env) {
    return FestivalBudgetProvider(
      cache: env.cache,
      repository: env.festivalBudgetRepository,
      transactions: env.transactionRepository,
      festivals: env.festivalService,
      dates: env.dates,
    );
  }

  static LoanProvider loans(AppEnvironment env) {
    return LoanProvider(cache: env.cache, repository: env.loanRepository);
  }

  static HouseholdProvider household(AppEnvironment env) {
    return HouseholdProvider(
      cache: env.cache,
      repository: env.householdRepository,
      dates: env.dates,
    );
  }

  static DashboardProvider dashboard(AppEnvironment env) {
    return DashboardProvider(
      cache: env.cache,
      transactions: env.transactionRepository,
      friends: env.friendRepository,
      budgets: env.budgetRepository,
      pasals: env.pasalRepository,
      recurring: env.recurringRepository,
      dates: env.dates,
    );
  }

  static ReportProvider reports(AppEnvironment env) {
    return ReportProvider(
      cache: env.cache,
      transactions: env.transactionRepository,
      budgets: env.budgetRepository,
      friends: env.friendRepository,
      pasals: env.pasalRepository,
      dates: env.dates,
      settings: env.settingsRepository,
    );
  }

  static AiInsightProvider aiInsight(
    AppEnvironment env, {
    FlameyController? flamey,
  }) {
    return AiInsightProvider(
      flamey: flamey,
      summaryService: FinancialSummaryService(
        transactions: env.transactionRepository,
        budgets: env.budgetRepository,
        settings: env.settingsRepository,
        dates: env.dates,
        pasals: env.pasalRepository,
      ),
      moodService: const AiMoodService(),
      insightService: AiInsightService(),
      weatherService: WeatherService(),
      cache: env.cache,
      // The flame's reaction arrives as an FCM push notification instead of
      // a speech bubble inside the balance card.
      onReaction: ReactionNotifier.deliver,
    );
  }
}
