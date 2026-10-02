import '../core/utils/currency_formatter.dart';
import '../models/ai_insight_model.dart';
import '../models/financial_summary.dart';
import 'insight_schedule.dart';
import 'spending_habits.dart';

/// Writes the suggestion shown on the home card from the user's own records,
/// on the device, with no network.
///
/// A suggestion has two parts:
///   * a line for the time of day ("You spent NPR 1,250 yesterday…"), and
///   * the strongest habit found in the data, said in one of three voices:
///     plain, playful, or a friendly roast.
///
/// Every figure in it is one [SpendingHabits] worked out, so nothing is ever
/// made up, and each suggestion carries the [AiInsight.basis] of its figure.
/// The choice of wording is deterministic: given the same data and the same
/// list of recently shown lines it always says the same thing, and it never
/// repeats the line it said last.
class SuggestionEngine {
  const SuggestionEngine({String Function(double amount)? money})
    : _money = money ?? _defaultMoney;

  final String Function(double amount) _money;

  static String _defaultMoney(double amount) =>
      CurrencyFormatter.format(amount);

  /// How playful a signal deserves to be. Flamey roasts whatever the records
  /// give it to roast: every habit worth worrying about, and the ones that
  /// are simply funny (a purchase that keeps coming back, one category taking
  /// most of the money, an open shop tab, a purchase far above the usual).
  /// Good news is never roasted; it is celebrated playfully. A mild fact
  /// that was roasted last time is only teased the next, so it is not all
  /// one note.
  static InsightTone toneFor(HabitSignal? signal, {InsightTone? lastTone}) {
    if (signal == null) return InsightTone.normal;
    if (signal.mood == HabitMood.good) return InsightTone.playful;
    final mild = signal.mood == HabitMood.neutral && signal.strength < 0.5;
    return mild && lastTone == InsightTone.roast
        ? InsightTone.playful
        : InsightTone.roast;
  }

  AiInsight build({
    required FinancialSummary summary,
    required InsightKind kind,
    required DateTime now,
    String? name,
    bool isBirthday = false,
    List<String> recent = const <String>[],
    InsightTone? lastTone,
  }) {
    final first = name?.trim().split(RegExp(r'\s+')).first;
    final who = first == null || first.isEmpty ? '' : ', $first';

    if (!summary.hasEnoughData) {
      return AiInsight(
        title: isBirthday ? 'Happy birthday 🎉' : 'Getting to know you',
        message:
            '${isBirthday ? 'Happy birthday$who! ' : _hello(kind, who)}'
            'Log a few more expenses and I will start spotting your habits.',
        category: 'general',
        priority: 'low',
        action: '',
        mood: isBirthday ? 'celebrating' : 'curious',
        source: InsightSource.placeholder,
        generatedAt: now,
        kind: kind.name,
        variant: 'placeholder',
      );
    }

    final habits = summary.habits;
    final signal = _choose(habits, kind, recent);
    final tone = toneFor(signal, lastTone: lastTone);
    final lead = _lead(kind, habits, who);

    String message;
    String title;
    String variant;
    if (signal == null) {
      message = lead;
      title = _kindTitle(kind);
      variant = '${kind.name}.plain';
    } else {
      final lines = _lines(signal, tone);
      final picked = _fresh(signal.kind, tone, lines, recent);
      variant = picked.id;
      title = picked.title;
      // The week's own comparison is the weekly line; saying it twice would
      // just be noise.
      final repeatsLead =
          kind == InsightKind.weekly &&
          (signal.kind == HabitKind.weekUp ||
              signal.kind == HabitKind.weekDown);
      message = repeatsLead ? picked.text : '$lead ${picked.text}';
    }
    if (isBirthday) message = 'Happy birthday$who! $message';

    return AiInsight(
      title: title,
      message: message,
      category: _category(signal),
      priority: signal == null
          ? 'low'
          : signal.mood == HabitMood.bad && signal.strength >= 0.7
          ? 'high'
          : 'normal',
      action: _action(signal),
      mood: _mood(kind, signal, tone),
      source: InsightSource.local,
      generatedAt: now,
      tone: tone,
      kind: kind.name,
      variant: variant,
      basis: signal?.basis,
    );
  }

  // --- which habit to talk about -----------------------------------------

  static HabitKind? _kindOf(String variant) {
    final name = variant.split('.').first;
    for (final kind in HabitKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  /// The strongest signal, unless it is the one talked about last time and
  /// there is something else worth saying.
  HabitSignal? _choose(
    SpendingHabits habits,
    InsightKind kind,
    List<String> recent,
  ) {
    final signals = habits.signals;
    if (signals.isEmpty) return null;
    final last = recent.isEmpty ? null : _kindOf(recent.last);
    for (final signal in signals) {
      if (signal.kind != last && signal.strength >= 0.35) return signal;
    }
    return signals.first;
  }

  // --- the line for the time of day --------------------------------------

  static String _hello(InsightKind kind, String who) => switch (kind) {
    InsightKind.morning => 'Good morning$who. ',
    InsightKind.evening || InsightKind.endOfDay => 'Good evening$who. ',
    _ => who.isEmpty ? '' : 'Hi${who.substring(1)}. ',
  };

  String _againstTypical(double amount, double typical) {
    if (typical <= 0) return '';
    if (amount > typical * 1.2) {
      return ', above your usual ${_money(typical)} a day';
    }
    if (amount < typical * 0.8) {
      return ', under your usual ${_money(typical)} a day';
    }
    return ', about your usual for a day';
  }

  String _lead(InsightKind kind, SpendingHabits h, String who) {
    switch (kind) {
      case InsightKind.morning:
        return h.spentYesterday <= 0
            ? 'Good morning$who. Nothing was spent yesterday.'
            : 'Good morning$who. You spent ${_money(h.spentYesterday)} '
                  'yesterday${_againstTypical(h.spentYesterday, h.typicalDay)}.';
      case InsightKind.midday:
        if (h.spentToday <= 0) return 'Nothing has been logged yet today.';
        final used = h.typicalUsedPercent;
        return used == null
            ? '${_money(h.spentToday)} spent so far today.'
            : 'You have already used ${used.round()}% of a typical day\'s '
                  'spending: ${_money(h.spentToday)} of about '
                  '${_money(h.typicalDay)}.';
      case InsightKind.evening:
        return h.spentToday <= 0
            ? 'No spending logged today so far.'
            : 'Today\'s spending so far is ${_money(h.spentToday)}'
                  '${_againstTypical(h.spentToday, h.typicalDay)}.';
      case InsightKind.endOfDay:
        if (h.spentToday <= 0) return 'Today closed with nothing spent.';
        final biggest = h.biggestToday;
        final count = h.countToday;
        final total =
            'Today came to ${_money(h.spentToday)} across $count '
            '${count == 1 ? 'purchase' : 'purchases'}.';
        return biggest == null || count < 2
            ? total
            : '$total The biggest was ${_money(biggest.amount)} on '
                  '${biggest.title.trim()}.';
      case InsightKind.weekly:
        final change = h.weekChangePercent;
        if (change == null) {
          return 'This week you spent ${_money(h.spentThisWeek)}.';
        }
        return 'This week you spent ${_money(h.spentThisWeek)}, '
            '${change.abs().round()}% ${change >= 0 ? 'more' : 'less'} than '
            'last week\'s ${_money(h.spentLastWeek)}.';
      case InsightKind.monthly:
        final parts = <String>['${_money(h.spentThisMonth)} spent'];
        if (h.incomeThisMonth > 0) {
          parts.add('${_money(h.incomeThisMonth)} earned');
        }
        final used = h.budgetUsedPercent;
        final budget = used == null
            ? ''
            : ', which is ${used.round()}% of your budget';
        final pace = h.projectedMonthSpend;
        final trend = pace == null || h.dayOfMonth >= h.daysInMonth
            ? ''
            : ' At this pace the month ends near ${_money(pace)}.';
        return 'This month so far: ${parts.join(' and ')}$budget.$trend';
    }
  }

  static String _kindTitle(InsightKind kind) => switch (kind) {
    InsightKind.morning => 'Good morning',
    InsightKind.midday => 'So far today',
    InsightKind.evening => 'Today so far',
    InsightKind.endOfDay => 'Today in review',
    InsightKind.weekly => 'This week',
    InsightKind.monthly => 'This month',
  };

  // --- the habit, in the chosen voice --------------------------------------

  /// The first wording not shown lately; if all were, the one shown longest
  /// ago.
  _Line _fresh(
    HabitKind kind,
    InsightTone tone,
    List<String> texts,
    List<String> recent,
  ) {
    final titles = _titles[kind]!;
    final title = switch (tone) {
      InsightTone.roast => titles.$3,
      InsightTone.playful => titles.$2,
      InsightTone.normal => titles.$1,
    };
    final lines = <_Line>[
      for (var i = 0; i < texts.length; i++)
        _Line('${kind.name}.${tone.name}.$i', title, texts[i]),
    ];
    for (final line in lines) {
      if (!recent.contains(line.id)) return line;
    }
    lines.sort(
      (a, b) => recent.lastIndexOf(a.id).compareTo(recent.lastIndexOf(b.id)),
    );
    return lines.first;
  }

  /// (plain, playful, roast) headline for each habit.
  static const Map<HabitKind, (String, String, String)> _titles =
      <HabitKind, (String, String, String)>{
        HabitKind.budgetOver: (
          'Over budget',
          'Budget has left the chat',
          'Budget has left the chat',
        ),
        HabitKind.categoryBudgetOver: (
          'A category is over budget',
          'One budget is gasping',
          'Fighting for its life',
        ),
        HabitKind.overIncome: (
          'Spending above income',
          'Outrunning your income',
          'Your wallet wants a word',
        ),
        HabitKind.budgetNear: (
          'Budget nearly used',
          'Budget on thin ice',
          'Even I burn slower',
        ),
        HabitKind.bigSpend: (
          'A large purchase',
          'That was a big one',
          'Your wallet felt that',
        ),
        HabitKind.weekUp: (
          'Spending is rising',
          'A warmer week',
          'The memo got lost',
        ),
        HabitKind.categorySurge: (
          'A category jumped',
          'Something got hungry',
          'Recovery day needed',
        ),
        HabitKind.smallPurchases: (
          'Small purchases add up',
          'Death by small buys',
          'Suspiciously many small buys',
        ),
        HabitKind.repeatPurchase: (
          'A regular purchase',
          'A familiar purchase',
          'Basically a subscription',
        ),
        HabitKind.topCategory: (
          'Where most of it goes',
          'The main character',
          'One category runs the show',
        ),
        HabitKind.pasalDue: ('Shop tabs', 'Tabs are open', 'The tab remembers'),
        HabitKind.savingWell: (
          'Saving well',
          'Character development',
          'Character development',
        ),
        HabitKind.weekDown: (
          'Spending is down',
          'A lighter week',
          'A lighter week',
        ),
        HabitKind.noSpendDays: (
          'No-spend days',
          'Wallet on holiday',
          'Wallet on holiday',
        ),
        HabitKind.streak: ('Logging streak', 'On a streak', 'On a streak'),
      };

  List<String> _lines(HabitSignal s, InsightTone tone) {
    final amount = _money(s.amount ?? 0);
    final other = _money(s.other ?? 0);
    final subject = s.subject ?? 'that';
    final count = s.count ?? 0;
    final percent = (s.percent ?? 0).round();
    final roast = tone == InsightTone.roast;
    final playful = tone == InsightTone.playful;

    switch (s.kind) {
      case HabitKind.budgetOver:
        if (roast) {
          return <String>[
            'Your budget of $other waved goodbye $amount ago. It is not '
                'coming back this month.',
            'You are $amount past the $other budget. At this point the '
                'budget is more of a suggestion.',
            'The $other budget lasted about as long as a New Year '
                'resolution. You are $amount past it and still going.',
          ];
        }
        if (playful) {
          return <String>[
            'The $other budget tapped out $amount ago. Easy does it for the '
                'rest of the month.',
          ];
        }
        return <String>['You are $amount over this month\'s budget of $other.'];
      case HabitKind.categoryBudgetOver:
        if (roast) {
          return <String>[
            'Bro, your $subject budget is fighting for its life: $amount '
                'spent against $other.',
            '$subject has eaten $amount of a $other budget. It did not even '
                'leave crumbs.',
            '$other was the plan for $subject. $amount is what happened. '
                'The plan never stood a chance.',
          ];
        }
        if (playful) {
          return <String>[
            '$subject has gone past its budget: $amount of $other. Maybe '
                'give it a rest.',
          ];
        }
        return <String>['$subject is over its budget: $amount of $other.'];
      case HabitKind.overIncome:
        if (roast) {
          return <String>[
            'You have spent $amount more than you earned this month. Your '
                'wallet would like a word.',
            'Spending is $amount ahead of income this month. Money is '
                'supposed to come in too, you know.',
            'You are living $amount beyond what came in this month. Bold, '
                'for someone without a money tree.',
          ];
        }
        if (playful) {
          return <String>[
            'Spending is running $amount ahead of income this month. Time '
                'to slow the pace a little.',
          ];
        }
        return <String>[
          'This month\'s spending is $amount above this month\'s income.',
        ];
      case HabitKind.budgetNear:
        final days = '$count ${count == 1 ? 'day' : 'days'}';
        if (roast) {
          return <String>[
            '$percent% of the budget is gone and there are still $days '
                'left. $amount has to survive all of them.',
            'You burned through $percent% of the budget with $days still '
                'to go. Even I do not burn that fast, and I am fire.',
            '$amount left for $days. Start practising the words "I already '
                'ate".',
          ];
        }
        if (playful) {
          return <String>[
            '$percent% of the budget is used with $days to go. $amount '
                'left: make it last.',
          ];
        }
        return <String>[
          '$percent% of this month\'s budget is used, with $amount left '
              'for $days.',
        ];
      case HabitKind.bigSpend:
        final times = (s.percent ?? 0).round();
        if (roast) {
          return <String>[
            '$amount on $subject, about $times times your usual purchase. '
                'Did the price tag come with a warning?',
            '$subject for $amount? Your wallet is still lying down: that is '
                'around $times times a normal purchase for you.',
          ];
        }
        if (playful) {
          return <String>[
            'Whoa: $amount on $subject. That is about $times times your '
                'usual purchase.',
            '$subject for $amount? That one stands out: around $times '
                'times a normal purchase for you.',
          ];
        }
        return <String>[
          '$subject at $amount is your largest recent purchase, about '
              '$times times a typical one.',
        ];
      case HabitKind.weekUp:
        if (roast) {
          return <String>[
            'You said you would save this week. Your transactions clearly '
                'did not get the memo: $amount against $other last week, '
                'up $percent%.',
            '$amount this week against $other last week. That is '
                '$percent% more, in case the wallet had not noticed.',
            'Up $percent% in a week: $amount against $other. If your income '
                'grew like your spending, you would be rich by now.',
          ];
        }
        if (playful) {
          return <String>[
            'This week is running $percent% hotter than last: $amount '
                'against $other.',
          ];
        }
        return <String>[
          'You have spent $amount in the last 7 days, $percent% more than '
              'the $other of the 7 days before.',
        ];
      case HabitKind.categorySurge:
        final before = (s.other ?? 0) <= 0
            ? 'nothing the week before'
            : '$other the week before';
        if (roast) {
          return <String>[
            '$subject went on a spree: $amount this week, from $before. '
                'Maybe give your wallet a recovery day.',
            '$amount on $subject this week, from $before. $subject is '
                'clearly having a moment.',
            '$subject took $amount off you this week, from $before. Blink '
                'twice if $subject is holding your wallet hostage.',
          ];
        }
        if (playful) {
          return <String>[
            'You have spent unusually much on $subject this week: '
                '$amount, from $before.',
          ];
        }
        return <String>['$subject is up this week: $amount, from $before.'];
      case HabitKind.smallPurchases:
        final limit = _money(
          s.other ?? SpendingHabitAnalyzer.smallPurchaseLimit,
        );
        if (roast) {
          return <String>[
            '$count purchases of $limit or less this week, $amount in '
                'total. Those little ones are adding up suspiciously fast 👀',
            '$count small buys this week came to $amount. Each one '
                'innocent, together a heist.',
            '$count rounds of "it is only a little" later, $amount is gone. '
                'The little ones hunt in packs.',
          ];
        }
        if (playful) {
          return <String>[
            'Small buys add up: $count of them this week came to $amount.',
          ];
        }
        return <String>[
          '$count purchases of $limit or less this week add up to $amount.',
        ];
      case HabitKind.repeatPurchase:
        if (roast) {
          return <String>[
            'At this point your $subject habit has a monthly '
                'subscription: $count times in 30 days, $amount in all.',
            '$subject again? That is $count times in 30 days and $amount. '
                'They should name a seat after you.',
            '$count rounds of $subject in 30 days for $amount. That is not '
                'a purchase any more, that is a relationship.',
          ];
        }
        if (playful) {
          return <String>[
            '$subject is a regular: $count times in 30 days, $amount in '
                'total.',
          ];
        }
        return <String>[
          'You bought $subject $count times in the last 30 days, $amount '
              'in total.',
        ];
      case HabitKind.topCategory:
        if (roast) {
          return <String>[
            '$subject is eating $percent% of everything you spend: $amount '
                'in 30 days. The other categories are extras in its film.',
            '$percent% of your money goes to $subject, $amount in 30 days. '
                'That is not a budget, that is a $subject fund.',
          ];
        }
        if (playful) {
          return <String>[
            '$subject is the main character: $percent% of everything you '
                'spent in 30 days, $amount.',
          ];
        }
        return <String>[
          '$subject takes $percent% of your spending: $amount in the last '
              '30 days.',
        ];
      case HabitKind.pasalDue:
        final shops = count <= 1 ? 'one shop tab' : '$count shop tabs';
        if (roast) {
          return <String>[
            'You owe $amount across $shops. The shopkeeper smiles at you '
                'for a reason.',
            '$amount on credit across $shops. "Put it on my tab" is not a '
                'savings plan.',
          ];
        }
        if (playful) {
          return <String>[
            'You owe $amount across $shops. Clearing one feels great, '
                'promise.',
          ];
        }
        return <String>['You owe $amount across $shops.'];
      case HabitKind.savingWell:
        if (playful || roast) {
          return <String>[
            'Okay, look at you actually saving money: $amount kept this '
                'month, $percent% of your income. Character development.',
            '$amount of this month\'s income is still yours, $percent% of '
                'it. Who is this responsible person?',
          ];
        }
        return <String>[
          'You have kept $amount of this month\'s income, $percent% of it.',
        ];
      case HabitKind.weekDown:
        if (playful || roast) {
          return <String>[
            'Spending is down $percent% on last week: $amount against '
                '$other. Your wallet says thank you.',
            '$amount this week, $other last week. That is $percent% less. '
                'Keep that energy.',
          ];
        }
        return <String>[
          'Spending is down $percent% on last week: $amount against $other.',
        ];
      case HabitKind.noSpendDays:
        if (playful || roast) {
          return <String>[
            '$count days in the last week with nothing spent. Your wallet '
                'got a proper rest.',
          ];
        }
        return <String>['$count of the last 7 days had no spending at all.'];
      case HabitKind.streak:
        if (s.strength >= 0.7) {
          return <String>[
            '$count days in a row of tracking. That is a milestone, and '
                'confetti is in order 🎉',
          ];
        }
        if (playful || roast) {
          return <String>[
            '$count days in a row of logging. That is a habit now.',
          ];
        }
        return <String>['You have logged spending $count days in a row.'];
    }
  }

  // --- what goes with it ----------------------------------------------------

  static String _category(HabitSignal? signal) => switch (signal?.kind) {
    HabitKind.budgetOver ||
    HabitKind.categoryBudgetOver ||
    HabitKind.budgetNear => 'budget',
    HabitKind.savingWell ||
    HabitKind.weekDown ||
    HabitKind.noSpendDays => 'saving',
    HabitKind.overIncome => 'income',
    HabitKind.streak || null => 'general',
    _ => 'spending',
  };

  /// A question for the chat, so the chip under the suggestion leads
  /// somewhere useful.
  static String _action(HabitSignal? signal) => switch (signal?.kind) {
    HabitKind.budgetOver ||
    HabitKind.budgetNear => 'How can I stay within my budget?',
    HabitKind.categoryBudgetOver ||
    HabitKind.categorySurge ||
    HabitKind.topCategory => 'How can I spend less on ${signal!.subject}?',
    HabitKind.overIncome ||
    HabitKind.weekUp => 'Where did my money go this week?',
    HabitKind.smallPurchases ||
    HabitKind.repeatPurchase => 'What are my most frequent purchases?',
    HabitKind.savingWell => 'How much have I saved this month?',
    _ => '',
  };

  /// The expression that fits what is being said.
  static String _mood(InsightKind kind, HabitSignal? signal, InsightTone tone) {
    if (signal != null) {
      switch (signal.kind) {
        case HabitKind.bigSpend:
          return tone == InsightTone.roast ? 'shocked' : 'surprised';
        case HabitKind.savingWell || HabitKind.weekDown:
          return 'proud';
        case HabitKind.streak:
          return signal.strength >= 0.7 ? 'celebrating' : 'happy';
        case HabitKind.noSpendDays:
          return 'happy';
        case HabitKind.topCategory || HabitKind.pasalDue:
          return switch (tone) {
            InsightTone.roast => 'roasting',
            InsightTone.playful => 'teasing',
            InsightTone.normal => 'curious',
          };
        default:
          return switch (tone) {
            InsightTone.roast => 'roasting',
            InsightTone.playful => 'teasing',
            InsightTone.normal => 'worried',
          };
      }
    }
    return switch (kind) {
      InsightKind.morning => 'happy',
      InsightKind.evening || InsightKind.endOfDay => 'thinking',
      _ => 'curious',
    };
  }
}

class _Line {
  const _Line(this.id, this.title, this.text);

  final String id;
  final String title;
  final String text;
}
