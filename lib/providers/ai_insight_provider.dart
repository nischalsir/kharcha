import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/errors/app_failure.dart';
import '../models/ai_chat_message.dart';
import '../models/ai_insight_model.dart';
import '../models/financial_summary.dart';
import '../services/ai_insight_service.dart';
import '../services/ai_mood_service.dart';
import '../services/cache_service.dart';
import '../services/financial_summary_service.dart';
import '../services/weather_service.dart';

/// Single source of truth for the Home-screen AI widgets (insight, mood,
/// streak, birthday wish, chat).
///
/// Responsibilities are intentionally split so the AI generation layer stays
/// reusable by a future FCM worker:
///   1. local aggregation  -> [FinancialSummaryService]
///   2. deterministic rules -> [AiMoodService]   (mood + streak + fallback)
///   3. remote generation   -> [AiInsightService] (backend, key never local)
///   4. caching + throttling -> this provider
///
/// The Home widget only ever *reads* this provider; it never calls the AI API
/// itself and never calls it during `build`.
class AiInsightProvider extends ChangeNotifier {
  AiInsightProvider({
    required this._summaryService,
    required this._moodService,
    required this._insightService,
    required this._weatherService,
    required this._cache,
    this.onReaction,
  });

  /// Delivers a transaction reaction outside the widget tree - in the app,
  /// as a device notification. Optional so tests and previews need no plugin.
  final Future<void> Function(AiMood reaction)? onReaction;

  final FinancialSummaryService _summaryService;
  final AiMoodService _moodService;
  final AiInsightService _insightService;
  final WeatherService _weatherService;
  final CacheService _cache;

  static const String _cacheKey = 'ai.insight.v1';
  static const String _cacheAtKey = 'ai.insight.v1.at';

  /// Don't auto-hit the network more often than this, and never twice within
  /// the (shorter) cool-down after a manual regenerate.
  static const Duration autoRefreshAfter = Duration(minutes: 30);
  static const Duration manualCooldown = Duration(seconds: 20);

  AiInsight? _insight;
  SpendingStreak _streak = const SpendingStreak(
    days: <StreakDay>[],
    activeDays: 0,
    currentStreak: 0,
  );
  AiMood? _mood;
  AiWeather? _weather;
  FinancialSummary? _summary;

  /// Transient mood shown right after a transaction is added, which takes
  /// priority over the time/weather mood until it expires.
  AiMood? _reaction;
  Timer? _reactionTimer;

  /// How long the mascot keeps reacting to a freshly added transaction.
  static const Duration reactionDuration = Duration(seconds: 10);

  bool _loading = false;
  bool _bootstrapped = false;
  String? _error;
  DateTime? _lastGeneratedAt;
  DateTime? _lastNetworkAttempt;

  final List<AiChatMessage> _chat = <AiChatMessage>[];
  bool _chatSending = false;

  String? _userName;
  bool _isBirthday = false;

  StreamSubscription<Set<dynamic>>? _cacheSub;
  Timer? _debounce;
  Timer? _clock;

  AiInsight? get insight => _insight;
  SpendingStreak get streak => _streak;

  /// The mood to show, with an active post-transaction reaction taking priority
  /// over the standing time/weather mood.
  AiMood? get mood => _reaction ?? _mood;

  /// The standing mood, ignoring any active reaction.
  AiMood? get restingMood => _mood;

  /// The transient transaction reaction, if the mascot is currently celebrating
  /// income or warning about a newly recorded expense.
  AiMood? get reaction => _reaction;

  AiWeather? get weather => _weather;
  FinancialSummary? get summary => _summary;
  bool get isLoading => _loading;
  bool get isBootstrapped => _bootstrapped;
  String? get error => _error;
  DateTime? get lastGeneratedAt => _lastGeneratedAt;
  String? get userName => _userName;
  bool get isBirthday => _isBirthday;
  List<AiChatMessage> get chat => List<AiChatMessage>.unmodifiable(_chat);
  bool get chatSending => _chatSending;

  /// One-time bootstrap: load cached insight instantly, compute local mood and
  /// streak, then refresh from the network only if the cache is stale.
  Future<void> ensureLoaded() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    await _loadCachedInsight();
    _recomputeLocal();
    notifyListeners();

    _cacheSub = _cache.changes.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 800), () {
        _recomputeLocal();
        notifyListeners();
      });
    });

    unawaited(_loadWeather());
    unawaited(refresh());
    _startMoodClock();
  }

  /// The mood depends on the wall clock, so it has to be re-evaluated even when
  /// no data changes — otherwise an app left open across a boundary would keep
  /// claiming it is "Good morning" at midnight.
  ///
  /// Notifications are only sent when the visible mood actually changes, so
  /// this stays quiet in the common case.
  void _startMoodClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(minutes: 5), (_) {
      final before = _moodSignature;
      _recomputeLocal();
      if (_moodSignature != before) notifyListeners();
    });
  }

  /// Makes the flame react to a transaction the user just added, then fall back
  /// to the standing mood after [reactionDuration].
  ///
  /// Called right after a successful save. Without it the mascot would keep
  /// whatever time/weather expression it had, so adding money and overspending
  /// would look identical.
  void reactToTransaction({
    required bool isIncome,
    required double amount,
    String? categoryName,
  }) {
    final summary = _summary ?? _emptySummary();
    _reaction = _moodService.buildReaction(
      isIncome: isIncome,
      amount: amount,
      summary: summary,
      categoryName: categoryName,
    );
    final reaction = _reaction!;
    final deliver = onReaction;
    if (deliver != null) {
      unawaited(
        deliver(reaction).catchError((Object error) {
          debugPrint('AI: could not post the reaction ($error)');
        }),
      );
    }
    _reactionTimer?.cancel();
    _reactionTimer = Timer(reactionDuration, () {
      _reaction = null;
      notifyListeners();
    });
    notifyListeners();
  }

  String? get _moodSignature {
    final mood = _mood;
    if (mood == null) return null;
    return '${mood.label}|${mood.face.name}|${mood.tone.name}|${mood.weatherLabel}';
  }

  /// Forgets everything that was worked out from one account's data: the
  /// cached insight, the chat and the name. Called when a different account
  /// takes over the device, before any of its screens are shown.
  Future<void> resetForAccount() async {
    _insight = null;
    _lastGeneratedAt = null;
    _lastNetworkAttempt = null;
    _error = null;
    _chat.clear();
    _userName = null;
    _isBirthday = false;
    _reaction = null;
    _reactionTimer?.cancel();
    _recomputeLocal();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheAtKey);
    } catch (_) {
      // Best effort; the in-memory copy is already gone.
    }
    if (_bootstrapped) unawaited(refresh());
  }

  /// Called by the Home widget with auth-derived context (name + birthday).
  void updateUser({String? name, required bool isBirthday}) {
    final changed = _userName != name || _isBirthday != isBirthday;
    _userName = name;
    _isBirthday = isBirthday;
    if (changed) notifyListeners();
  }

  /// Regenerates the insight. `force` bypasses the auto-refresh interval (used
  /// by the manual refresh button) but still respects a short cool-down.
  Future<void> refresh({bool force = false}) async {
    if (_loading) return;
    final now = DateTime.now();
    if (!force) {
      final last = _lastGeneratedAt;
      if (last != null && now.difference(last) < autoRefreshAfter) return;
    } else {
      final attempt = _lastNetworkAttempt;
      if (attempt != null && now.difference(attempt) < manualCooldown) return;
    }

    _loading = true;
    _error = null;
    notifyListeners();
    _lastNetworkAttempt = now;

    try {
      final generated = await _insightService.generateInsight(
        context: _contextPayload(),
      );
      _insight = generated;
      _lastGeneratedAt = generated.generatedAt;
      await _persistInsight(generated);
    } catch (error) {
      // Graceful degradation: fall back to the deterministic local insight so
      // the card is never empty, but surface a soft error for the UI.
      final local = _moodService.localInsight(_summary ?? _emptySummary());
      _insight = local;
      _error = error is AppFailure
          ? error.message
          : 'Could not reach the AI right now.';
      _lastGeneratedAt ??= local.generatedAt;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> regenerate() => refresh(force: true);

  /// Fixed-topic finance Q&A grounded in the user's own summary.
  Future<void> sendChat(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _chatSending) return;

    _chat.add(
      AiChatMessage(text: trimmed, fromUser: true, sentAt: DateTime.now()),
    );
    final placeholder = AiChatMessage(
      text: 'Thinking…',
      fromUser: false,
      sentAt: DateTime.now(),
      pending: true,
    );
    _chat.add(placeholder);
    _chatSending = true;
    notifyListeners();

    try {
      final reply = await _insightService.ask(
        trimmed,
        context: _contextPayload(),
      );
      _replacePlaceholder(reply);
    } catch (_) {
      _replacePlaceholder(
        'I could not reach the AI just now. Please try again shortly.',
        failed: true,
      );
    } finally {
      _chatSending = false;
      notifyListeners();
    }
  }

  void _replacePlaceholder(String text, {bool failed = false}) {
    final index = _chat.lastIndexWhere((m) => m.pending);
    if (index >= 0) {
      _chat[index] = AiChatMessage(
        text: text,
        fromUser: false,
        sentAt: DateTime.now(),
        failed: failed,
      );
    }
  }

  // --- internals -----------------------------------------------------------

  void _recomputeLocal() {
    try {
      final summary = _summaryService.build();
      _summary = summary;
      _streak = _moodService.buildStreak(summary);
      _mood = _moodService.buildMood(
        summary: summary,
        now: DateTime.now(),
        weather: _weather,
      );
    } catch (_) {
      // A malformed cached row must never crash the dashboard.
    }
  }

  Future<void> _loadWeather() async {
    final weather = await _weatherService.current();
    if (weather == null) return;
    _weather = weather;
    _recomputeLocal();
    notifyListeners();
  }

  Map<String, dynamic> _contextPayload() {
    final now = DateTime.now();
    return <String, dynamic>{
      'hour': now.hour,
      'weekday': now.weekday,
      'isBirthday': _isBirthday,
      if (_userName != null) 'name': _userName,
      if (_weather != null) 'weather': _weather!.label,
    };
  }

  FinancialSummary _emptySummary() {
    final now = DateTime.now();
    return FinancialSummary(
      expenseThisWeek: 0,
      expensePreviousWeek: 0,
      expenseThisMonth: 0,
      incomeThisMonth: 0,
      budgetTotal: 0,
      topCategory: null,
      topCategoryAmount: 0,
      dailyExpense: <({DateTime day, double amount})>[(day: now, amount: 0)],
      activeDays: 0,
      transactionCount: 0,
    );
  }

  Future<void> _loadCachedInsight() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      final at = prefs.getString(_cacheAtKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final cached = AiInsight.fromJson(
        Map<String, dynamic>.from(decoded),
        source: InsightSource.ai,
      );
      if (cached.message.isEmpty) return;
      _insight = cached;
      _lastGeneratedAt = at != null
          ? DateTime.tryParse(at)
          : cached.generatedAt;
    } catch (_) {
      // Ignore corrupt cache.
    }
  }

  Future<void> _persistInsight(AiInsight insight) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(insight.toJson()));
      await prefs.setString(_cacheAtKey, insight.generatedAt.toIso8601String());
    } catch (_) {
      // Caching is best-effort.
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _debounce?.cancel();
    _reactionTimer?.cancel();
    _cacheSub?.cancel();
    super.dispose();
  }
}
