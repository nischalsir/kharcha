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
import '../services/flamey_controller.dart';
import '../services/insight_schedule.dart';
import '../services/spending_habits.dart';
import '../services/suggestion_engine.dart';
import '../services/weather_service.dart';

/// Why a suggestion is being looked at again.
enum InsightTrigger {
  /// The app opened, or came back to the front.
  appOpened,

  /// A new time window began (morning, midday, evening, end of day, and the
  /// weekly and monthly ones).
  windowChanged,

  /// A transaction or a budget was added, edited or removed.
  dataChanged,

  /// The user pulled the page down to refresh it.
  manual,
}

/// Single source of truth for the Home-screen AI widgets (suggestion, mood,
/// streak, birthday wish, chat), and the one place that decides *when* a
/// suggestion is made.
///
/// ## How a suggestion comes about
///
/// Nothing on screen asks for one. The suggestion is looked at again only
/// when something meaningful happens:
///
///   * a new time window begins ([InsightSchedule]): morning, midday,
///     evening, end of day, Saturday evening for the week, and three days a
///     month for the month;
///   * the user's records change: a transaction or a budget is added, edited
///     or removed (seen as a change in [_signatureOf]);
///   * the app is opened or comes back to the front.
///
/// Each time, two things happen in order:
///
///   1. [SuggestionEngine] writes a suggestion on the device, at once, from
///      the user's own records. This is what is shown. It costs nothing and
///      needs no connection.
///   2. If a version written by the AI for this exact window and data has not
///      been fetched yet, and the network budget allows, the backend is asked
///      for one, which replaces the local one when it arrives.
///
/// Step 2 is bounded three ways: at most one request per window-and-data
/// state ([_aiKey]), a minimum gap between requests ([dataRefreshGap]), and a
/// daily ceiling ([maxNetworkPerDay]). Rebuilding a page, opening the app
/// again in the same window with the same data, or Flamey changing
/// expression never causes a request.
///
/// Responsibilities stay split so each part is testable on its own:
///   * local aggregation   -> [FinancialSummaryService]
///   * the words           -> [SuggestionEngine], [AiMoodService]
///   * remote generation   -> [AiInsightService] (backend; key never local)
///   * when, and caching   -> this provider
class AiInsightProvider extends ChangeNotifier {
  AiInsightProvider({
    required this._summaryService,
    required this._moodService,
    required this._insightService,
    required this._weatherService,
    required this._cache,
    this.onReaction,
    this._flamey,
    this._engine = const SuggestionEngine(),
    this._schedule = const InsightSchedule(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Delivers a transaction reaction outside the widget tree - in the app,
  /// as a device notification. Optional so tests and previews need no plugin.
  final Future<void> Function(AiMood reaction)? onReaction;

  final FinancialSummaryService _summaryService;
  final AiMoodService _moodService;
  final AiInsightService _insightService;
  final WeatherService _weatherService;
  final CacheService _cache;
  final FlameyController? _flamey;
  final SuggestionEngine _engine;
  final InsightSchedule _schedule;
  final DateTime Function() _clock;

  static const String _cacheKey = 'ai.insight.v1';
  static const String _cacheAtKey = 'ai.insight.v1.at';
  static const String _stateKey = 'ai.insight.v2.state';

  /// The least time between two requests caused by data changing, so adding
  /// five expenses in a row asks once, not five times.
  static const Duration dataRefreshGap = Duration(minutes: 3);

  /// The least time between any two requests, however they were caused.
  /// Just over the server's own limit of one request per 30 seconds, so a
  /// request is never made only to be refused.
  static const Duration minimumGap = Duration(seconds: 35);

  /// A ceiling on requests in one day. Four windows and a handful of data
  /// changes fit well inside it; a bug that loops does not.
  static const int maxNetworkPerDay = 24;

  /// How many shown wordings are remembered, so they are not repeated.
  static const int _rememberedLines = 10;

  AiInsight? _insight;
  SpendingStreak _streak = const SpendingStreak(
    days: <StreakDay>[],
    activeDays: 0,
    currentStreak: 0,
  );
  AiMood? _mood;
  AiWeather? _weather;
  FinancialSummary? _summary;

  /// The window and the data the shown suggestion was written for.
  String? _windowKey;
  String? _signature;

  /// The window-and-data state an AI-written suggestion was last fetched for.
  String? _aiKey;
  List<String> _recent = <String>[];
  InsightTone? _lastTone;

  /// The tone before the one on screen, for rewriting the same suggestion
  /// without it changing voice.
  InsightTone? _toneBefore;
  String? _networkDay;
  int _networkCalls = 0;

  /// Transient mood shown right after a transaction is added, which takes
  /// priority over the time/weather mood until it expires.
  AiMood? _reaction;
  Timer? _reactionTimer;

  /// How long the mascot keeps reacting to a freshly added transaction.
  static const Duration reactionDuration = Duration(seconds: 10);

  bool _loading = false;
  bool _bootstrapped = false;
  bool _disposed = false;
  String? _error;
  DateTime? _lastGeneratedAt;
  DateTime? _lastNetworkAttempt;

  final List<AiChatMessage> _chat = <AiChatMessage>[];
  bool _chatSending = false;

  String? _userName;
  bool _isBirthday = false;

  StreamSubscription<Set<dynamic>>? _cacheSub;
  Timer? _debounce;
  Timer? _clockTimer;

  /// The one timer of the scheduler: fires at the next window boundary, or
  /// when a request that had to wait for [dataRefreshGap] may be made.
  Timer? _scheduleTimer;

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

  /// True while the AI is writing a version of the current suggestion. The
  /// suggestion on screen stays readable throughout.
  bool get isLoading => _loading;
  bool get isBootstrapped => _bootstrapped;
  String? get error => _error;
  DateTime? get lastGeneratedAt => _lastGeneratedAt;
  String? get userName => _userName;
  bool get isBirthday => _isBirthday;
  List<AiChatMessage> get chat => List<AiChatMessage>.unmodifiable(_chat);
  bool get chatSending => _chatSending;

  /// The time window the shown suggestion belongs to, e.g.
  /// `2026-10-01:morning`.
  String? get windowKey => _windowKey;

  /// How many requests have been made to the AI today.
  @visibleForTesting
  int get networkCallsToday => _networkCalls;

  /// The expression that goes with the suggestion on screen.
  FlameyExpression get insightExpression {
    final insight = _insight;
    if (insight == null) return FlameyExpression.curious;
    return FlameyExpression.forInsight(
      mood: insight.mood,
      tone: insight.tone.name,
    );
  }

  /// One-time bootstrap: load the cached suggestion instantly, compute local
  /// mood and streak, then let the schedule decide whether anything is due.
  Future<void> ensureLoaded() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    await _loadCached();
    _recomputeLocal(announce: false);
    _evaluate(InsightTrigger.appOpened);
    notifyListeners();

    _cacheSub = _cache.changes.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 800), () {
        if (_disposed) return;
        _recomputeLocal(announce: true);
        _evaluate(InsightTrigger.dataChanged);
        notifyListeners();
      });
    });

    unawaited(_loadWeather());
    _startMoodClock();
  }

  /// The app came back to the front: a window may have changed while it was
  /// away.
  void onAppResumed() {
    if (!_bootstrapped || _disposed) return;
    _recomputeLocal(announce: false);
    _evaluate(InsightTrigger.appOpened);
    notifyListeners();
  }

  /// The optional manual fallback (pull to refresh). Subject to the same
  /// minimum gap, so it cannot be used to hammer the backend.
  Future<void> refresh({bool force = false}) async {
    if (_disposed) return;
    // Asked for by hand: the AI may write this state again.
    if (force) _aiKey = null;
    _recomputeLocal(announce: false);
    _evaluate(force ? InsightTrigger.manual : InsightTrigger.appOpened);
    notifyListeners();
  }

  /// The mood depends on the wall clock, so it has to be re-evaluated even when
  /// no data changes — otherwise an app left open across a boundary would keep
  /// claiming it is "Good morning" at midnight.
  ///
  /// Notifications are only sent when the visible mood actually changes, so
  /// this stays quiet in the common case.
  void _startMoodClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      final before = _moodSignature;
      _recomputeLocal(announce: false);
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
      now: _clock(),
    );
    final reaction = _reaction!;
    // The same face, with its motion, on the interactive Flamey.
    _flamey?.send(
      isIncome ? FlameyEvent.savedMoney : FlameyEvent.transaction,
      face: reaction.face,
      hold: reactionDuration,
    );
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
      if (!_disposed) notifyListeners();
    });
    notifyListeners();
  }

  String? get _moodSignature {
    final mood = _mood;
    if (mood == null) return null;
    return '${mood.label}|${mood.face.name}|${mood.tone.name}|${mood.weatherLabel}';
  }

  /// Forgets everything that was worked out from one account's data: the
  /// cached suggestion, what was said lately, the chat and the name. Called
  /// when a different account takes over the device, before any of its
  /// screens are shown.
  Future<void> resetForAccount() async {
    _insight = null;
    _windowKey = null;
    _signature = null;
    _aiKey = null;
    _recent = <String>[];
    _lastTone = null;
    _toneBefore = null;
    _lastGeneratedAt = null;
    _lastNetworkAttempt = null;
    _error = null;
    _chat.clear();
    _userName = null;
    _isBirthday = false;
    _reaction = null;
    _reactionTimer?.cancel();
    _scheduleTimer?.cancel();
    _recomputeLocal(announce: false);
    if (_bootstrapped) _evaluate(InsightTrigger.appOpened);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheAtKey);
      await prefs.remove(_stateKey);
    } catch (_) {
      // Best effort; the in-memory copy is already gone.
    }
  }

  /// Called by the Home widget with auth-derived context (name + birthday).
  void updateUser({String? name, required bool isBirthday}) {
    final changed = _userName != name || _isBirthday != isBirthday;
    _userName = name;
    _isBirthday = isBirthday;
    if (!changed) return;
    // The greeting names the user, so it is rewritten; nothing is fetched.
    if (_bootstrapped &&
        _summary != null &&
        _insight?.source != InsightSource.ai) {
      _writeLocal(_currentWindow(), _signatureOf(_summary!), announce: false);
    }
    notifyListeners();
  }

  // --- the scheduler -------------------------------------------------------

  InsightWindow _currentWindow() {
    final habits = _summary?.habits ?? SpendingHabits.empty;
    return _schedule.windowAt(
      _clock(),
      dayOfMonth: habits.dayOfMonth,
      daysInMonth: habits.daysInMonth,
    );
  }

  /// What a suggestion depends on. Any transaction or budget being added,
  /// edited or removed moves at least one of these, as does the pattern that
  /// stands out most changing.
  static String _signatureOf(FinancialSummary summary) {
    final habits = summary.habits;
    final top = habits.signals.isEmpty ? '-' : habits.signals.first.kind.name;
    return '${summary.transactionCount}|${habits.spentToday.round()}|'
        '${habits.spentThisMonth.round()}|${habits.incomeThisMonth.round()}|'
        '${habits.budgetTotal.round()}|$top';
  }

  /// Decides what, if anything, to do about the suggestion. Cheap to call:
  /// when nothing meaningful has changed it does nothing.
  void _evaluate(InsightTrigger trigger) {
    final summary = _summary;
    if (summary == null || _disposed) return;
    final window = _currentWindow();
    final signature = _signatureOf(summary);

    final windowChanged = window.key != _windowKey;
    final dataChanged = signature != _signature;
    if (windowChanged || dataChanged || _insight == null) {
      // A suggestion the AI already wrote for exactly this state stays.
      final state = '${window.key}|$signature';
      if (!(_aiKey == state && _insight?.source == InsightSource.ai)) {
        _writeLocal(window, signature, announce: true);
      }
    }

    _maybeAskAi(
      window,
      signature,
      windowChanged
          ? InsightTrigger.windowChanged
          : dataChanged
          ? InsightTrigger.dataChanged
          : trigger,
    );
    _armScheduleTimer();
  }

  /// Writes the suggestion on the device and shows it.
  void _writeLocal(
    InsightWindow window,
    String signature, {
    required bool announce,
  }) {
    final summary = _summary;
    if (summary == null) return;
    // Writing the same state again (the name arrived, say) must give the
    // same line in the same voice, not move on to the next one.
    final again =
        window.key == _windowKey &&
        signature == _signature &&
        _recent.isNotEmpty &&
        _recent.last == _insight?.variant;
    final local = _engine.build(
      summary: summary,
      kind: window.kind,
      now: _clock(),
      name: _userName,
      isBirthday: _isBirthday,
      recent: again ? _recent.sublist(0, _recent.length - 1) : _recent,
      lastTone: again ? _toneBefore : _lastTone,
    );
    final changed =
        _insight?.variant != local.variant ||
        _insight?.message != local.message;
    _insight = local;
    _windowKey = window.key;
    _signature = signature;
    _lastGeneratedAt = local.generatedAt;
    _remember(local);
    unawaited(_persist());
    if (changed && announce) _announce(local);
  }

  void _remember(AiInsight insight) {
    final variant = insight.variant;
    if (variant != null && (_recent.isEmpty || _recent.last != variant)) {
      _recent = <String>[..._recent, variant];
      if (_recent.length > _rememberedLines) {
        _recent = _recent.sublist(_recent.length - _rememberedLines);
      }
      _toneBefore = _lastTone;
    }
    _lastTone = insight.tone;
  }

  /// Flamey takes the expression of what is being said. A local signal: no
  /// request is ever made for the sake of an expression.
  void _announce(AiInsight insight) {
    _flamey?.send(
      FlameyEvent.suggestion,
      expression: FlameyExpression.forInsight(
        mood: insight.mood,
        tone: insight.tone.name,
      ),
    );
  }

  String _today() {
    final now = _clock();
    return '${now.year}-${now.month}-${now.day}';
  }

  /// Asks the backend for an AI-written suggestion when one is due and the
  /// budget allows. Otherwise does nothing, or sets a timer for when it may.
  void _maybeAskAi(
    InsightWindow window,
    String signature,
    InsightTrigger trigger,
  ) {
    final summary = _summary;
    if (summary == null || _loading || !summary.hasEnoughData) return;
    if (!_insightService.canCall) return;
    final state = '${window.key}|$signature';
    if (_aiKey == state) return;

    final now = _clock();
    if (_networkDay != _today()) {
      _networkDay = _today();
      _networkCalls = 0;
    }
    if (_networkCalls >= maxNetworkPerDay) return;

    final last = _lastNetworkAttempt;
    final gap = trigger == InsightTrigger.dataChanged
        ? dataRefreshGap
        : minimumGap;
    if (last != null && now.difference(last) < gap) {
      // Too soon. Look again when the gap has passed, so the latest state
      // still gets its suggestion, once.
      _deferUntil(last.add(gap));
      return;
    }
    unawaited(_askAi(window, signature, state));
  }

  Future<void> _askAi(
    InsightWindow window,
    String signature,
    String state,
  ) async {
    _loading = true;
    _error = null;
    _lastNetworkAttempt = _clock();
    _networkCalls++;
    // Marked before the reply: one request per state, whether it succeeds
    // or fails, so a backend that is down is not retried on every change.
    _aiKey = state;
    _flamey?.send(FlameyEvent.thinking);
    notifyListeners();

    try {
      final generated = await _insightService.generateInsight(
        context: _contextPayload(window),
      );
      if (_disposed) return;
      // The world moved on while the AI was writing: its answer is for a
      // window or for data that are no longer current.
      final current = _currentWindow();
      if (current.key != window.key ||
          _summary == null ||
          _signatureOf(_summary!) != signature) {
        _flamey?.settle();
        return;
      }
      final insight = generated.copyWith(kind: window.kind.name);
      _insight = insight;
      _lastGeneratedAt = insight.generatedAt;
      _lastTone = insight.tone;
      _announce(insight);
    } catch (error) {
      // The suggestion written on the device is already on screen; the AI
      // version simply did not arrive.
      _error = error is AppFailure
          ? error.message
          : 'Could not reach the AI right now.';
      _flamey?.settle();
    } finally {
      _loading = false;
      unawaited(_persist());
      if (!_disposed) {
        // Records may have changed while the AI was writing. If so, that
        // newer state is owed a suggestion too, after the usual gap.
        final latest = _summary;
        if (latest != null) {
          _maybeAskAi(
            _currentWindow(),
            _signatureOf(latest),
            InsightTrigger.dataChanged,
          );
        }
        notifyListeners();
      }
    }
  }

  void _deferUntil(DateTime when) {
    final next = _schedule.nextChange(_clock());
    _setScheduleTimer(when.isBefore(next) ? when : next);
  }

  void _armScheduleTimer() {
    if (_scheduleTimer?.isActive ?? false) return;
    _setScheduleTimer(_schedule.nextChange(_clock()));
  }

  void _setScheduleTimer(DateTime when) {
    _scheduleTimer?.cancel();
    if (_disposed) return;
    var wait = when.difference(_clock()) + const Duration(seconds: 1);
    if (wait.isNegative) wait = const Duration(seconds: 1);
    _scheduleTimer = Timer(wait, () {
      _scheduleTimer = null;
      if (_disposed) return;
      _recomputeLocal(announce: false);
      _evaluate(InsightTrigger.windowChanged);
      notifyListeners();
    });
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
    _flamey?.send(FlameyEvent.thinking);
    notifyListeners();

    try {
      final reply = await _insightService.ask(
        trimmed,
        context: _contextPayload(_currentWindow()),
      );
      _replacePlaceholder(reply);
      _flamey?.send(FlameyEvent.suggestion);
    } catch (_) {
      _replacePlaceholder(
        'I could not reach the AI just now. Please try again shortly.',
        failed: true,
      );
      _flamey?.send(FlameyEvent.error);
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

  /// Rebuilds the summary, streak and mood from the cache. With [announce],
  /// Flamey also reacts to a line being crossed since the last time: the
  /// budget passed, a streak milestone, saving a good share of income.
  void _recomputeLocal({required bool announce}) {
    try {
      final before = _summary?.habits;
      final summary = _summaryService.build();
      _summary = summary;
      _streak = _moodService.buildStreak(summary);
      _mood = _moodService.buildMood(
        summary: summary,
        now: _clock(),
        weather: _weather,
      );
      if (announce && before != null) {
        _announceCrossings(before, summary.habits);
      }
    } catch (_) {
      // A malformed cached row must never crash the dashboard.
    }
  }

  void _announceCrossings(SpendingHabits before, SpendingHabits after) {
    final flamey = _flamey;
    if (flamey == null) return;
    bool appeared(HabitKind kind) =>
        before.signal(kind) == null && after.signal(kind) != null;
    final streak = after.signal(HabitKind.streak);
    final milestone =
        streak != null &&
        streak.strength >= 0.7 &&
        before.signal(HabitKind.streak)?.count != streak.count;
    if (appeared(HabitKind.budgetOver) ||
        appeared(HabitKind.categoryBudgetOver)) {
      flamey.send(FlameyEvent.overspent);
    } else if (milestone) {
      flamey.send(FlameyEvent.goalReached);
    } else if (appeared(HabitKind.savingWell)) {
      flamey.send(FlameyEvent.savedMoney, expression: FlameyExpression.proud);
    }
  }

  Future<void> _loadWeather() async {
    final weather = await _weatherService.current();
    if (weather == null || _disposed) return;
    _weather = weather;
    _recomputeLocal(announce: false);
    notifyListeners();
  }

  Map<String, dynamic> _contextPayload(InsightWindow window) {
    final now = _clock();
    final signals = _summary?.habits.signals ?? const <HabitSignal>[];
    final tone = SuggestionEngine.toneFor(
      signals.isEmpty ? null : signals.first,
      lastTone: _lastTone,
    );
    return <String, dynamic>{
      'hour': now.hour,
      'weekday': now.weekday,
      'isBirthday': _isBirthday,
      if (_userName != null) 'name': _userName,
      if (_weather != null) 'weather': _weather!.label,
      // What the suggestion is for, and how playful it may be. The server
      // works the numbers out itself; none are sent from here.
      'kind': window.kind.name,
      'tone': tone.name,
      'utcOffsetMinutes': now.timeZoneOffset.inMinutes,
      // So the AI does not open the same way twice running.
      if (_insight != null) 'avoid': <String>[_insight!.title],
    };
  }

  FinancialSummary _emptySummary() {
    final now = _clock();
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

  Future<void> _loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final state = prefs.getString(_stateKey);
      if (state != null) {
        final decoded = jsonDecode(state);
        if (decoded is Map) {
          _windowKey = decoded['window'] as String?;
          _signature = decoded['signature'] as String?;
          _aiKey = decoded['aiKey'] as String?;
          _recent = <String>[
            for (final line
                in (decoded['recent'] as List? ?? const <dynamic>[]))
              if (line is String) line,
          ];
          final tone = decoded['lastTone'];
          _lastTone = tone is String ? InsightTone.fromName(tone) : null;
          _networkDay = decoded['networkDay'] as String?;
          _networkCalls = (decoded['networkCalls'] as num?)?.toInt() ?? 0;
        }
      }
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final cached = AiInsight.fromJson(Map<String, dynamic>.from(decoded));
      if (cached.message.isEmpty) return;
      _insight = cached;
      final at = prefs.getString(_cacheAtKey);
      _lastGeneratedAt = at != null
          ? DateTime.tryParse(at)
          : cached.generatedAt;
    } catch (_) {
      // Ignore corrupt cache.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final insight = _insight;
      if (insight != null) {
        await prefs.setString(_cacheKey, jsonEncode(insight.toJson()));
        await prefs.setString(
          _cacheAtKey,
          insight.generatedAt.toIso8601String(),
        );
      }
      await prefs.setString(
        _stateKey,
        jsonEncode(<String, dynamic>{
          'window': _windowKey,
          'signature': _signature,
          'aiKey': _aiKey,
          'recent': _recent,
          'lastTone': _lastTone?.name,
          'networkDay': _networkDay,
          'networkCalls': _networkCalls,
        }),
      );
    } catch (_) {
      // Caching is best-effort.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _clockTimer?.cancel();
    _debounce?.cancel();
    _reactionTimer?.cancel();
    _scheduleTimer?.cancel();
    _cacheSub?.cancel();
    super.dispose();
  }
}
