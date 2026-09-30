import 'dart:math' as math;

import '../core/utils/currency_formatter.dart';
import '../models/ai_insight_model.dart';
import '../models/financial_summary.dart';
import 'weather_service.dart';

/// Business rules that turn a [FinancialSummary] + the current time + optional
/// weather into a mood, a streak strip, and a local fallback insight.
///
/// No network, no state. The only non-determinism is which line of dialogue is
/// picked from a pool, and that goes through an injectable [math.Random] so
/// tests can pin it.
class AiMoodService {
  const AiMoodService({this._random});

  final math.Random? _random;

  static final math.Random _defaultRandom = math.Random();

  math.Random get _rng => _random ?? _defaultRandom;

  T _pick<T>(List<T> options) => options[_rng.nextInt(options.length)];

  SpendingStreak buildStreak(FinancialSummary summary, {int days = 14}) {
    final average = summary.dailyAverage;
    final recent = summary.dailyExpense.length <= days
        ? summary.dailyExpense
        : summary.dailyExpense.sublist(summary.dailyExpense.length - days);

    final result = <StreakDay>[];
    for (final entry in recent) {
      final status = entry.amount <= 0
          ? StreakStatus.none
          : (average <= 0 || entry.amount <= average * 1.15)
          ? StreakStatus.good
          : StreakStatus.over;
      result.add(
        StreakDay(day: entry.day, amount: entry.amount, status: status),
      );
    }

    var current = 0;
    for (var i = result.length - 1; i >= 0; i--) {
      if (result[i].status == StreakStatus.none) break;
      current++;
    }

    return SpendingStreak(
      days: result,
      activeDays: summary.activeDays,
      currentStreak: current,
    );
  }

  /// The flame's "energy", 0..1, from how this month's money is going.
  ///
  /// The backbone is the savings rate: keeping all of this month’s income is
  /// 1.0, breaking even is 0.5, spending double your income is 0. Weekly trend,
  /// budget pressure and today's pace then nudge it, so a single good or bad
  /// day is visible without swamping the month.
  double energyFor(FinancialSummary summary) {
    final income = summary.incomeThisMonth;
    final expense = summary.expenseThisMonth;

    double energy;
    if (income > 0) {
      final savingsRate = ((income - expense) / income).clamp(-1.0, 1.0);
      energy = 0.5 + savingsRate * 0.5;
    } else {
      // No income logged yet: neutral, sliding down as spending piles up.
      energy = expense <= 0 ? 0.5 : 0.4;
    }

    final change = summary.weeklyChangePct;
    if (change != null && change <= -10) energy += 0.08;
    if (change != null && change >= 25) energy -= 0.1;

    final used = summary.budgetUsedPct;
    if (used != null && used >= 100) {
      energy -= 0.15;
    } else if (used != null && used >= 85) {
      energy -= 0.07;
    }

    final average = summary.dailyAverage;
    final today = summary.dailyExpense.isEmpty
        ? 0.0
        : summary.dailyExpense.last.amount;
    if (average > 0 && today > average * 1.3) energy -= 0.07;

    return energy.clamp(0.0, 1.0);
  }

  AiMood buildMood({
    required FinancialSummary summary,
    required DateTime now,
    AiWeather? weather,
  }) {
    final hour = now.hour;
    final energy = energyFor(summary);
    final level = _levelFor(energy);

    // Late night: the flame is asleep, but its colour still shows how the
    // money is doing.
    if (hour >= 23 || hour < 5) {
      return AiMood(
        emoji: '😴',
        label: 'Sleepy',
        message: _pick(const <String>[
          'Zzz… it\'s late. Your money will still be here in the morning 🌙',
          'Yawn… time to rest. We\'ll count coins tomorrow 😴',
          'Shhh, the flame is napping. Good night! 🌙',
        ]),
        tone: level.tone,
        face: MoodFace.sleepy,
        weatherLabel: weather?.label,
        energy: energy,
      );
    }

    final greeting = hour < 12
        ? 'Good morning! '
        : hour >= 17
        ? 'Good evening! '
        : '';

    // About half the time the flame offers a concrete tip built from the
    // user's own numbers instead of a one-liner. On a steady day it "thinks"
    // while doing so; happy and worried moods keep their own face.
    final suggestion = _rng.nextBool() ? _suggestionFor(summary, level) : null;
    final face = suggestion != null && level == _MoodLevel.steady
        ? MoodFace.thinking
        : level.face;

    return AiMood(
      emoji: suggestion != null && level == _MoodLevel.steady ? '🤔' : level.emoji,
      label: level.label,
      message:
          '$greeting${suggestion ?? _pick(level.lines)}${_weatherSuffix(weather)}',
      tone: level.tone,
      face: _faceFor(face, weather),
      weatherLabel: weather?.label,
      energy: energy,
    );
  }

  /// A practical, number-backed tip for the current mood, or a general money
  /// habit when there is nothing specific to say.
  String _suggestionFor(FinancialSummary summary, _MoodLevel level) {
    final tips = <String>[];
    final top = summary.topCategory;
    if (top != null && summary.topCategoryAmount > 0) {
      tips.add(
        'Most of your money went to $top '
        '(${CurrencyFormatter.format(summary.topCategoryAmount)}). '
        'Try a small limit on it this week 🎯',
      );
    }
    final used = summary.budgetUsedPct;
    if (used != null && used >= 60 && used < 100) {
      final left = summary.budgetTotal - summary.expenseThisMonth;
      tips.add(
        '${used.round()}% of your budget is used. '
        '${CurrencyFormatter.format(left)} left — plan it before it plans you 📋',
      );
    }
    final change = summary.weeklyChangePct;
    if (change != null && change >= 15) {
      tips.add(
        'Spending is up ${change.round()}% on last week. Skip one treat to '
        'balance it out 🍩➡️💰',
      );
    }
    if (summary.incomeThisMonth <= 0) {
      tips.add(
        'Add this month’s income so I can tell how you’re really doing 💼',
      );
    } else if (summary.incomeThisMonth > summary.expenseThisMonth) {
      final saved = summary.incomeThisMonth - summary.expenseThisMonth;
      tips.add(
        'You’re ${CurrencyFormatter.format(saved)} ahead this month. Move '
        'some into savings now, before it quietly gets spent 🏦',
      );
    }
    if (level == _MoodLevel.careful || level == _MoodLevel.low) {
      tips.addAll(const <String>[
        'Cash-only for small buys this week makes every rupee feel real 💵',
        'Cook at home twice this week — easy savings 🍛',
      ]);
    }
    tips.addAll(_generalTips);
    return _pick(tips);
  }

  static const List<String> _generalTips = <String>[
    'Wait 24 hours before any non-essential buy. Still want it? Go ahead 🕐',
    'Check your subscriptions — one forgotten one is pure savings 📺',
    'Pay yourself first: move a little to savings the day income lands 🐷',
    'Split shared bills in Friends so nobody forgets who owes what 🤝',
    'A monthly budget makes me much better at warning you early 📊',
    'Log spends right away — tiny amounts add up faster than you think 📝',
    'Before a festival, set aside a fixed amount for gifts and food 🪔',
    'Compare prices at two shops before any big purchase 🛒',
  ];

  /// A short-lived reaction to a transaction the user just added.
  ///
  /// Income always lifts the flame. An expense is graded against the user's own
  /// daily average so a routine coffee does not scold them, while a genuinely
  /// large spend does.
  AiMood buildReaction({
    required bool isIncome,
    required double amount,
    required FinancialSummary summary,
    String? categoryName,
  }) {
    final money = CurrencyFormatter.format(amount);
    final where = categoryName?.trim();
    final on = (where == null || where.isEmpty) ? '' : ' on $where';
    final into = (where == null || where.isEmpty) ? '' : ' — $where';
    final before = energyFor(summary);

    if (isIncome) {
      final average = summary.dailyAverage;
      final jackpot = average > 0
          ? amount >= average * 10
          : amount >= summary.incomeThisMonth && amount > 0;
      if (jackpot) {
        return AiMood(
          emoji: '😍',
          label: 'Jackpot',
          message: _pick(<String>[
            'Hmmmm… MONEY! 😍 $money$into?! I’m in love.',
            'Whoa, $money! My heart eyes can’t handle this 💖',
            '$money landed! Save a slice before anything else, promise? 🥰',
            'Jackpot! $money in. Future you says thank you 💰',
          ]),
          tone: MoodTone.good,
          face: MoodFace.love,
          energy: 1.0,
        );
      }
      return AiMood(
        emoji: '🤑',
        label: 'Money in',
        message: _pick(<String>[
          'Hmmmm… money! 🤑 $money landed$into. I\'m glowing!',
          'Mmm, $money! Yummy yummy money 😋 Keep it coming!',
          'Cha-ching! $money in$into. The flame is on FIRE 🔥',
          '$money?! Yayyy! 🎊 Best. Day. Ever.',
          'Oooh, $money! Let\'s save a little of this, okay? 😍',
        ]),
        tone: MoodTone.good,
        face: MoodFace.excited,
        energy: math.min(1.0, before + 0.3),
      );
    }

    final average = summary.dailyAverage;
    final heavy = average > 0 && amount > average * 1.3;
    final veryHeavy = average > 0 && amount > average * 2.5;

    if (veryHeavy) {
      return AiMood(
        emoji: '😱',
        label: 'Big spend',
        message: _pick(<String>[
          'Noooo… $money$on?! Save money, please! 😢',
          'Ouch. $money gone$on. My flame is shrinking… 💸',
          'Woah, $money out! Let\'s save money for a few days 🙏',
          '$money$on… that\'s a lot. Save money, save me! 😰',
        ]),
        tone: MoodTone.bad,
        face: MoodFace.shocked,
        energy: math.max(0.0, before - 0.3),
      );
    }

    if (heavy) {
      return AiMood(
        emoji: '😬',
        label: 'Watch it',
        message: _pick(<String>[
          'Hmm, $money$on. A bit much today — save money? 🤔',
          '$money out$on. Easy there, save some for later 😬',
          'Spending is above your usual pace. Save money mode? 🐢',
          'Noted: $money$on. Let\'s keep the rest of today light.',
        ]),
        tone: MoodTone.warn,
        face: MoodFace.worried,
        energy: math.max(0.0, before - 0.15),
      );
    }

    return AiMood(
      emoji: '🙂',
      label: 'Logged',
      message: _pick(<String>[
        'Got it! $money$on. Small spends, no stress 📝',
        'Tracked $money$on. Still burning bright 🔥',
        '$money noted$on. Remember to save a little too!',
        'Done! $money recorded$on. You\'re in control 💪',
      ]),
      tone: MoodTone.neutral,
      face: MoodFace.wink,
      energy: math.max(0.0, before - 0.05),
    );
  }

  _MoodLevel _levelFor(double energy) {
    if (energy >= 0.8) return _MoodLevel.thrilled;
    if (energy >= 0.6) return _MoodLevel.happy;
    if (energy >= 0.42) return _MoodLevel.steady;
    if (energy >= 0.25) return _MoodLevel.careful;
    return _MoodLevel.low;
  }

  /// Lets heavy weather soften a positive mood and spoil a neutral one, so the
  /// mascot visibly reacts to the sky without ever contradicting the numbers.
  ///
  /// Sad and worried faces are never brightened by the weather.
  MoodFace _faceFor(MoodFace base, AiWeather? weather) {
    if (weather == null) return base;
    if (base == MoodFace.sad) return base;
    final code = weather.code;
    if (code >= 95) {
      return base == MoodFace.excited ? MoodFace.happy : MoodFace.worried;
    }
    if (code >= 71 && code <= 77) {
      return base == MoodFace.worried ? base : MoodFace.calm;
    }
    if (code >= 51 && code <= 82) {
      return switch (base) {
        MoodFace.excited => MoodFace.happy,
        MoodFace.worried => MoodFace.worried,
        _ => MoodFace.calm,
      };
    }
    return base;
  }

  /// Deterministic offline insight built from real numbers only.
  AiInsight localInsight(FinancialSummary summary) {
    if (!summary.hasEnoughData) {
      return AiInsight(
        title: 'Smart Tip',
        message: 'Keep tracking your expenses to unlock personalised insights.',
        category: 'general',
        priority: 'low',
        action: '',
        mood: 'neutral',
        source: InsightSource.placeholder,
        generatedAt: DateTime.now(),
      );
    }

    final change = summary.weeklyChangePct;
    if (change != null && change >= 15) {
      return _local(
        title: 'Spending is rising',
        message:
            'This week you spent ${change.round()}% more than last week.${_topSuffix(summary)}',
        category: 'spending',
        priority: 'high',
        action: 'Review this week\'s expenses',
      );
    }
    final usedPct = summary.budgetUsedPct;
    if (usedPct != null && usedPct >= 85) {
      return _local(
        title: 'Budget nearly used',
        message:
            'You have used ${usedPct.round()}% of your monthly budget. Consider easing off.',
        category: 'budget',
        priority: 'high',
        action: 'Check your budget',
      );
    }
    if (change != null && change <= -10) {
      return _local(
        title: 'Spending is down',
        message:
            'Nicely done — spending is ${change.abs().round()}% lower than last week.',
        category: 'saving',
        priority: 'normal',
        action: '',
      );
    }
    return _local(
      title: 'Stay on track',
      message:
          'You have logged ${summary.activeDays} active days this month. Keep the momentum going.',
      category: 'general',
      priority: 'low',
      action: '',
    );
  }

  AiInsight _local({
    required String title,
    required String message,
    required String category,
    required String priority,
    required String action,
  }) {
    return AiInsight(
      title: title,
      message: message,
      category: category,
      priority: priority,
      action: action,
      mood: 'neutral',
      source: InsightSource.local,
      generatedAt: DateTime.now(),
    );
  }

  String _topSuffix(FinancialSummary summary) {
    final top = summary.topCategory;
    if (top == null || summary.topCategoryAmount <= 0) return '';
    return ' Biggest category: $top.';
  }

  String _weatherSuffix(AiWeather? weather) {
    if (weather == null) return '';
    return ' ${weather.emoji} ${weather.hint}';
  }
}

/// The five standing moods, from a glowing flame down to a flickering one.
enum _MoodLevel {
  thrilled(
    emoji: '🤑',
    label: 'Loving it',
    tone: MoodTone.good,
    face: MoodFace.excited,
    lines: <String>[
      'Hmmmm… money! Your savings are looking delicious 🤑',
      'Look at all that saved money! I\'m glowing ✨',
      'Rich vibes only. Keep this up! 😎',
    ],
  ),
  happy(
    emoji: '😄',
    label: 'Happy',
    tone: MoodTone.good,
    face: MoodFace.happy,
    lines: <String>[
      'Income is ahead of spending. Nice work! 😄',
      'We\'re saving this month — the flame feels great 🔥',
      'Good balance so far. Keep the spending light 👍',
    ],
  ),
  steady(
    emoji: '🙂',
    label: 'Steady',
    tone: MoodTone.neutral,
    face: MoodFace.calm,
    lines: <String>[
      'Things look steady. Keep tracking 🙂',
      'Spending and income are about even. Save a little extra?',
      'All calm here. A small saving today goes a long way.',
    ],
  ),
  careful(
    emoji: '😬',
    label: 'Careful',
    tone: MoodTone.warn,
    face: MoodFace.worried,
    lines: <String>[
      'Spending is catching up with income. Save money! 😬',
      'Hmm, money is going out fast. Slow down a bit? 🐢',
      'Let\'s skip the extras for a few days. Save money 🙏',
    ],
  ),
  low(
    emoji: '😢',
    label: 'Low',
    tone: MoodTone.bad,
    face: MoodFace.sad,
    lines: <String>[
      'Spending is more than income… my flame is getting low 😢',
      'Save money, please! I\'m running out of fuel 💸',
      'Rough month. Every rupee saved helps me glow again 🥺',
    ],
  );

  const _MoodLevel({
    required this.emoji,
    required this.label,
    required this.tone,
    required this.face,
    required this.lines,
  });

  final String emoji;
  final String label;
  final MoodTone tone;
  final MoodFace face;
  final List<String> lines;
}
