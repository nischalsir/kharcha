import 'dart:math' as math;

import '../core/utils/currency_formatter.dart';
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

  /// The option last chosen from each pool, so it is not chosen again next.
  static final Map<String, int> _lastPick = <String, int>{};

  /// Like [_pick], but never the option this pool returned last time.
  T _pickFresh<T>(String pool, List<T> options) {
    if (options.length == 1) return options.first;
    var index = _rng.nextInt(options.length);
    if (index == _lastPick[pool]) {
      index = (index + 1 + _rng.nextInt(options.length - 1)) % options.length;
    }
    _lastPick[pool] = index;
    return options[index];
  }

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
          'Shhh, Flamey is napping. Good night! 🌙',
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
        : _standingFace(level, energy, summary);

    return AiMood(
      emoji: suggestion != null && level == _MoodLevel.steady
          ? '🤔'
          : level.emoji,
      label: level.label,
      message:
          '$greeting${suggestion ?? _pickFresh('mood-${level.name}', level.lines)}${_weatherSuffix(weather)}',
      tone: level.tone,
      face: _faceFor(face, weather),
      weatherLabel: weather?.label,
      energy: energy,
    );
  }

  /// The face for a standing mood. Mostly the level's own, with a few
  /// variations so a good month is not the same grin every time the app opens.
  MoodFace _standingFace(
    _MoodLevel level,
    double energy,
    FinancialSummary summary,
  ) {
    final used = summary.budgetUsedPct;
    switch (level) {
      case _MoodLevel.thrilled:
        return _pick(const <MoodFace>[
          MoodFace.excited,
          MoodFace.excited,
          MoodFace.cool,
          MoodFace.starstruck,
        ]);
      case _MoodLevel.happy:
        return used != null && used < 60 && _rng.nextInt(3) == 0
            ? MoodFace.cool
            : level.face;
      case _MoodLevel.careful:
        return used != null && used >= 100 ? MoodFace.grumpy : level.face;
      case _MoodLevel.low:
        // Spending at double the income or worse: past sad.
        return energy <= 0.08 ? MoodFace.crying : level.face;
      case _MoodLevel.steady:
        return level.face;
    }
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
    return _pickFresh('tip', tips);
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
  /// large spend does. Within each grade there are many lines, faces and
  /// titles, flavoured by the category and the time of day, and the same one
  /// is never used twice in a row: this is sent as a notification, and the
  /// same sentence every time reads like a broken record.
  AiMood buildReaction({
    required bool isIncome,
    required double amount,
    required FinancialSummary summary,
    String? categoryName,
    DateTime? now,
  }) {
    final money = CurrencyFormatter.format(amount);
    final where = categoryName?.trim();
    final hasWhere = where != null && where.isNotEmpty;
    final on = hasWhere ? ' on $where' : '';
    final into = hasWhere ? ' — $where' : '';
    final before = energyFor(summary);
    final average = summary.dailyAverage;
    final hour = (now ?? DateTime.now()).hour;
    final lateNight = hour >= 23 || hour < 5;

    AiMood react(
      String key,
      List<_Line> lines, {
      required MoodTone tone,
      required double energy,
    }) {
      final line = _pickFresh(key, lines);
      return AiMood(
        emoji: line.emoji,
        label: line.label,
        message: line.text,
        tone: tone,
        face: line.face,
        energy: energy,
      );
    }

    if (isIncome) {
      final jackpot = average > 0
          ? amount >= average * 10
          : amount >= summary.incomeThisMonth && amount > 0;
      if (jackpot) {
        return react(
          'jackpot',
          <_Line>[
            _Line(
              '😍',
              'Jackpot',
              MoodFace.love,
              'Hmmmm… MONEY! 😍 $money$into?! I’m in love.',
            ),
            _Line(
              '💖',
              'Jackpot',
              MoodFace.love,
              'Whoa, $money! My heart eyes can’t handle this 💖',
            ),
            _Line(
              '🤩',
              'Big money day',
              MoodFace.starstruck,
              '$money landed! Save a slice before anything else, promise? 🥰',
            ),
            _Line(
              '🎉',
              'Payday party',
              MoodFace.party,
              'Jackpot! $money in. Future you says thank you 💰',
            ),
            _Line(
              '🤩',
              'Stars in my eyes',
              MoodFace.starstruck,
              '$money$into! I can see the savings goal from here ⭐',
            ),
            _Line(
              '🎊',
              'Payday party',
              MoodFace.party,
              'Confetti time! $money just arrived. Put some away first 🎊',
            ),
            _Line(
              '💰',
              'Big money day',
              MoodFace.love,
              '$money in one go! Pay yourself first, then enjoy the rest 💛',
            ),
            _Line(
              '🥳',
              'Jackpot',
              MoodFace.party,
              'That is a LOT of fuel: $money. I’m burning golden tonight 🔥',
            ),
          ],
          tone: MoodTone.good,
          energy: 1.0,
        );
      }
      return react(
        'income',
        <_Line>[
          _Line(
            '🤑',
            'Money in',
            MoodFace.excited,
            'Hmmmm… money! 🤑 $money landed$into. I’m glowing!',
          ),
          _Line(
            '😋',
            'Yummy money',
            MoodFace.yum,
            'Mmm, $money! Yummy yummy money 😋 Keep it coming!',
          ),
          _Line(
            '🔥',
            'Cha-ching',
            MoodFace.excited,
            'Cha-ching! $money in$into. Flamey is on FIRE 🔥',
          ),
          _Line(
            '🎊',
            'Money in',
            MoodFace.happy,
            '$money?! Yayyy! 🎊 Today just got better.',
          ),
          _Line(
            '😍',
            'Wallet fed',
            MoodFace.yum,
            'Oooh, $money! Let’s save a little of this, okay? 😍',
          ),
          _Line(
            '😎',
            'Looking good',
            MoodFace.cool,
            '$money added$into. Smooth. Very smooth 😎',
          ),
          _Line(
            '💪',
            'Money in',
            MoodFace.happy,
            'Nice one! $money in. That’s how the month gets won 💪',
          ),
          _Line(
            '✨',
            'Cha-ching',
            MoodFace.excited,
            '$money just walked in$into. Welcome, welcome ✨',
          ),
          _Line(
            '🐷',
            'Wallet fed',
            MoodFace.yum,
            'Fed with $money! Slip a bit into savings while it’s fresh 🐷',
          ),
          _Line(
            '📈',
            'Looking good',
            MoodFace.cool,
            'Income up by $money. The numbers are smiling 📈',
          ),
        ],
        tone: MoodTone.good,
        energy: math.min(1.0, before + 0.3),
      );
    }

    final heavy = average > 0 && amount > average * 1.3;
    final veryHeavy = average > 0 && amount > average * 2.5;
    final used = summary.budgetUsedPct;

    if (veryHeavy) {
      return react(
        'very-heavy',
        <_Line>[
          _Line(
            '😱',
            'Big spend',
            MoodFace.shocked,
            'Noooo… $money$on?! Save money, please! 😢',
          ),
          _Line(
            '💸',
            'Big spend',
            MoodFace.shocked,
            'Ouch. $money gone$on. My flame is shrinking… 💸',
          ),
          _Line(
            '😵',
            'Head spinning',
            MoodFace.dizzy,
            'Woah, $money out! Let’s save money for a few days 🙏',
          ),
          _Line(
            '😰',
            'Big spend',
            MoodFace.shocked,
            '$money$on… that’s a lot. Save money, save me! 😰',
          ),
          _Line(
            '😵‍💫',
            'Head spinning',
            MoodFace.dizzy,
            '$money in one go$on. I need to sit down for a second 😵‍💫',
          ),
          _Line(
            '😭',
            'That hurt',
            MoodFace.crying,
            '$money$on! I felt that one. Quiet few days now, deal? 😭',
          ),
          _Line(
            '🧯',
            'Big spend',
            MoodFace.shocked,
            'That’s several days of spending at once: $money$on 🧯',
          ),
          _Line(
            '😭',
            'That hurt',
            MoodFace.crying,
            'There goes $money$on. Hold me, and hold the wallet 🥺',
          ),
        ],
        tone: MoodTone.bad,
        energy: math.max(0.0, before - 0.3),
      );
    }

    if (used != null && used >= 100) {
      return react(
        'over-budget',
        <_Line>[
          _Line(
            '😤',
            'Over budget',
            MoodFace.grumpy,
            '$money more$on, and the budget is already used up 😤',
          ),
          _Line(
            '😤',
            'Over budget',
            MoodFace.grumpy,
            'Budget’s gone and we’re still spending: $money$on. Hmph.',
          ),
          _Line(
            '🚨',
            'Budget blown',
            MoodFace.grumpy,
            'That’s $money past the budget line$on. Let’s stop here today 🚨',
          ),
          _Line(
            '😬',
            'Budget blown',
            MoodFace.worried,
            '$money$on on top of a full budget. Only needs from here, okay?',
          ),
        ],
        tone: MoodTone.bad,
        energy: math.max(0.0, before - 0.2),
      );
    }

    if (heavy) {
      return react(
        'heavy',
        <_Line>[
          _Line(
            '😬',
            'Watch it',
            MoodFace.worried,
            'Hmm, $money$on. A bit much today — save money? 🤔',
          ),
          _Line(
            '😬',
            'Watch it',
            MoodFace.worried,
            '$money out$on. Easy there, save some for later 😬',
          ),
          _Line(
            '🐢',
            'Slow down',
            MoodFace.worried,
            'Spending is above your usual pace. Save money mode? 🐢',
          ),
          _Line(
            '🤔',
            'Hmm',
            MoodFace.thinking,
            'Noted: $money$on. Let’s keep the rest of today light.',
          ),
          _Line(
            '🤔',
            'Hmm',
            MoodFace.thinking,
            '$money$on is more than a normal day for you. Worth it? 🤔',
          ),
          _Line(
            '⚠️',
            'Slow down',
            MoodFace.worried,
            'That’s a chunky one: $money$on. Small spends only now ⚠️',
          ),
          _Line(
            '🫣',
            'Watch it',
            MoodFace.worried,
            '$money$on. I’m peeking at the balance through my fingers 🫣',
          ),
          _Line(
            '🧮',
            'Hmm',
            MoodFace.thinking,
            '$money logged$on. Skip one extra later and we’re even 🧮',
          ),
        ],
        tone: MoodTone.warn,
        energy: math.max(0.0, before - 0.15),
      );
    }

    return react(
      'light',
      <_Line>[
        _Line(
          '🙂',
          'Logged',
          MoodFace.wink,
          'Got it! $money$on. Small spends, no stress 📝',
        ),
        _Line(
          '🔥',
          'Logged',
          MoodFace.wink,
          'Tracked $money$on. Still burning bright 🔥',
        ),
        _Line(
          '📝',
          'Noted',
          MoodFace.calm,
          '$money noted$on. Remember to save a little too!',
        ),
        _Line(
          '💪',
          'Logged',
          MoodFace.happy,
          'Done! $money recorded$on. You’re in control 💪',
        ),
        _Line(
          '😉',
          'Got it',
          MoodFace.wink,
          '$money$on, written down before it could hide 😉',
        ),
        _Line(
          '😎',
          'All good',
          MoodFace.cool,
          '$money$on. Well within your usual. Carry on 😎',
        ),
        _Line(
          '✅',
          'Noted',
          MoodFace.happy,
          'Logged $money$on. Every entry makes my advice sharper ✅',
        ),
        _Line(
          '🙂',
          'Got it',
          MoodFace.calm,
          '$money$on. Nothing to worry about here.',
        ),
        _Line(
          '👌',
          'All good',
          MoodFace.wink,
          'Small one: $money$on. That’s the way to do it 👌',
        ),
        _Line(
          '📒',
          'Noted',
          MoodFace.calm,
          '$money$on is in the book. Thanks for keeping it honest 📒',
        ),
        // Flavoured lines go last so the plain ones keep their positions.
        ..._categoryLines(where, money),
        if (lateNight)
          _Line(
            '🌙',
            'Night owl',
            MoodFace.sleepy,
            '$money$on at this hour? Logged. Now bed, both of us 🌙',
          ),
        if (hour >= 5 && hour < 10)
          _Line(
            '☀️',
            'Early bird',
            MoodFace.happy,
            'First spend of the morning: $money$on. Noted ☀️',
          ),
      ],
      tone: MoodTone.neutral,
      energy: math.max(0.0, before - 0.05),
    );
  }

  /// Extra lines for an everyday expense when the category says what it was.
  static List<_Line> _categoryLines(String? category, String money) {
    final name = category?.toLowerCase() ?? '';
    bool any(List<String> words) => words.any(name.contains);

    if (any(const <String>[
      'food',
      'restaurant',
      'coffee',
      'tea',
      'snack',
      'khaja',
      'grocer',
      'dining',
      'lunch',
      'dinner',
      'breakfast',
    ])) {
      return <_Line>[
        _Line(
          '😋',
          'Yum',
          MoodFace.yum,
          '$money on food. Hope it was delicious 😋',
        ),
        _Line(
          '🍛',
          'Yum',
          MoodFace.yum,
          'Fuel for you: $money. Fuel for me is savings 🍛',
        ),
      ];
    }
    if (any(const <String>[
      'transport',
      'fuel',
      'petrol',
      'diesel',
      'bus',
      'taxi',
      'ride',
      'travel',
      'fare',
    ])) {
      return <_Line>[
        _Line(
          '🛵',
          'On the move',
          MoodFace.wink,
          '$money to get around. Safe travels 🛵',
        ),
        _Line(
          '🚌',
          'On the move',
          MoodFace.calm,
          'Travel logged: $money. Walking is free, just saying 🚶',
        ),
      ];
    }
    if (any(const <String>[
      'shop',
      'cloth',
      'fashion',
      'electronic',
      'gadget',
    ])) {
      return <_Line>[
        _Line(
          '🛍️',
          'Treat logged',
          MoodFace.cool,
          '$money on shopping. Looking sharp, spending sharp 🛍️',
        ),
        _Line(
          '🤔',
          'Treat logged',
          MoodFace.thinking,
          'New things for $money. Need or want? Either way, noted 🤔',
        ),
      ];
    }
    if (any(const <String>[
      'bill',
      'rent',
      'electric',
      'internet',
      'water',
      'recharge',
      'topup',
      'top-up',
      'utilit',
      'phone',
    ])) {
      return <_Line>[
        _Line(
          '🧾',
          'Bill paid',
          MoodFace.happy,
          '$money bill sorted. One less thing on your mind 🧾',
        ),
        _Line(
          '✅',
          'Bill paid',
          MoodFace.cool,
          'Paid on time: $money. Responsible looks good on you ✅',
        ),
      ];
    }
    if (any(const <String>[
      'health',
      'medic',
      'hospital',
      'doctor',
      'pharma',
    ])) {
      return <_Line>[
        _Line(
          '💊',
          'Take care',
          MoodFace.calm,
          '$money on health. Money well spent. Get well soon 💊',
        ),
      ];
    }
    if (any(const <String>[
      'educat',
      'school',
      'college',
      'tuition',
      'book',
      'course',
      'fee',
    ])) {
      return <_Line>[
        _Line(
          '📚',
          'Investing in you',
          MoodFace.cool,
          '$money on learning. The best kind of spending 📚',
        ),
      ];
    }
    if (any(const <String>[
      'entertain',
      'movie',
      'game',
      'music',
      'fun',
      'party',
    ])) {
      return <_Line>[
        _Line(
          '🎬',
          'Fun logged',
          MoodFace.party,
          '$money on fun. You earned a little joy 🎬',
        ),
      ];
    }
    if (any(const <String>['gift', 'festival', 'donat', 'charity', 'puja'])) {
      return <_Line>[
        _Line(
          '🎁',
          'Kind heart',
          MoodFace.love,
          '$money for someone else. That warms me right up 🎁',
        ),
      ];
    }
    return const <_Line>[];
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
    const low = <MoodFace>{MoodFace.sad, MoodFace.crying, MoodFace.grumpy};
    const bright = <MoodFace>{
      MoodFace.excited,
      MoodFace.cool,
      MoodFace.starstruck,
    };
    if (low.contains(base)) return base;
    final code = weather.code;
    if (code >= 95) {
      return bright.contains(base) ? MoodFace.happy : MoodFace.worried;
    }
    if (code >= 71 && code <= 77) {
      return base == MoodFace.worried ? base : MoodFace.calm;
    }
    if (code >= 51 && code <= 82) {
      if (bright.contains(base)) return MoodFace.happy;
      return base == MoodFace.worried ? base : MoodFace.calm;
    }
    return base;
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
      'Most of this month’s income is still yours. Beautiful 💛',
      'I’m burning gold today. You did that 🔥',
      'Saving like this, the goal comes to you 🎯',
    ],
  ),
  happy(
    emoji: '😄',
    label: 'Happy',
    tone: MoodTone.good,
    face: MoodFace.happy,
    lines: <String>[
      'Income is ahead of spending. Nice work! 😄',
      'We\'re saving this month — Flamey feels great 🔥',
      'Good balance so far. Keep the spending light 👍',
      'More coming in than going out. That’s the whole game 🙌',
      'Comfortably ahead this month. Keep doing what you’re doing 😊',
      'A healthy month so far. Tuck a little away? 🐷',
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
      'Even keel. One skipped extra tips this month into saving ⚖️',
      'Nothing dramatic today, which is exactly how I like it 🙂',
      'Holding steady. Check the budget once and carry on 📊',
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
      'It’s getting tight. Needs first, wants next month 🧾',
      'A few careful days now saves a hard week later ⏳',
      'I’m flickering a bit. Go easy on the wallet today? 🕯️',
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
      'More went out than came in. Let’s make today a no-spend day 🙏',
      'I’m down to an ember. One quiet week and I’ll be back 🕯️',
      'Tough stretch. Pick the one expense to cut and cut it ✂️',
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

/// One way the flame can react: the notification's emoji and title, the face
/// it pulls, and what it says.
class _Line {
  const _Line(this.emoji, this.label, this.face, this.text);

  final String emoji;
  final String label;
  final MoodFace face;
  final String text;
}
