import { assertEquals, assertThrows } from 'jsr:@std/assert@1';
import { buildHabits, type HabitRow } from '../_shared/habits.ts';
import { quotedNumbers, ungroundedNumbers } from '../_shared/grounding.ts';
import { validateInsight } from '../_shared/insight_validation.ts';
import {
  buildInsightUserPrompt,
  INSIGHT_SYSTEM_PROMPT,
  PROMPT_VERSION,
} from '../_shared/prompt.ts';

// 2026-03-10 14:00 in Nepal (UTC+5:45).
const NOW = new Date('2026-03-10T08:15:00Z');
const NEPAL = 345;

/** A purchase `daysAgo` days back, at `hour` Nepal time. */
function spend(
  daysAgo: number,
  amount: number,
  title = 'Tea',
  category = 'Food',
  hour = 12,
): HabitRow {
  const local = Date.UTC(2026, 2, 10 - daysAgo, hour, 0, 0) - NEPAL * 60_000;
  return {
    amount,
    type: 'expense',
    occurred_at: new Date(local).toISOString(),
    title,
    category,
  };
}

const income = (daysAgo: number, amount: number): HabitRow => ({
  ...spend(daysAgo, amount, 'Salary', 'Income'),
  type: 'income',
});

Deno.test('habits: today, yesterday and a typical day are the user\'s own days', () => {
  const habits = buildHabits(
    [
      spend(0, 300, 'Lunch'),
      spend(0, 120, 'Bus', 'Transport'),
      spend(1, 800, 'Groceries'),
      spend(2, 400),
      spend(10, 1300),
    ],
    NOW,
    NEPAL,
  );
  assertEquals(habits.localDate, '2026-03-10');
  assertEquals(habits.today, {
    spent: 420,
    count: 2,
    biggest: { title: 'Lunch', amount: 300 },
  });
  assertEquals(habits.yesterday, { spent: 800, count: 1 });
  // 2,500 spent before today, first of it 10 days ago: 250 a day.
  assertEquals(habits.typicalDay, 250);
  assertEquals(habits.typicalUsedPct, 168);
});

Deno.test('habits: the day turns at midnight in Nepal, not in UTC', () => {
  // 00:30 on the 10th in Nepal is 18:45 on the 9th in UTC.
  const late = spend(0, 500, 'Night snack', 'Food', 0);
  assertEquals(late.occurred_at.slice(0, 10), '2026-03-09');
  const habits = buildHabits([late], NOW, NEPAL);
  assertEquals(habits.today.spent, 500);
  assertEquals(habits.yesterday.spent, 0);
  // Read as UTC days the same purchase would have been yesterday's.
  assertEquals(buildHabits([late], NOW, 0).today.spent, 0);
});

Deno.test('habits: week against week, movers, repeats, small buys, saving', () => {
  const rows: HabitRow[] = [
    income(3, 50000),
    // This week: food jumps, lots of small tea.
    spend(0, 2500, 'Restaurant'),
    spend(1, 2500, 'Restaurant'),
    spend(2, 1500, 'Restaurant'),
    ...Array.from({ length: 9 }, (_, i) => spend(i % 6, 60, 'Tea')),
    // Last week.
    spend(8, 1000, 'Restaurant'),
    spend(9, 1000, 'Rent', 'Home'),
    spend(20, 900, 'Restaurant'),
  ];
  const habits = buildHabits(rows, NOW, NEPAL);
  assertEquals(habits.week, { spent: 7040, previous: 2000, changePct: 252 });
  assertEquals(habits.categoryMovers[0], {
    name: 'Food',
    thisWeek: 7040,
    lastWeek: 1000,
    changePct: 604,
  });
  assertEquals(habits.repeats[0], { title: 'Restaurant', count: 5, total: 8400 });
  assertEquals(habits.repeats[1], { title: 'Tea', count: 9, total: 540 });
  assertEquals(habits.smallPurchases, { limit: 250, count: 9, total: 540 });
  assertEquals(habits.last30Days, {
    spent: 9940,
    income: 50000,
    saved: 40060,
    savedPct: 80,
  });
  // Against nine 60-rupee teas, a 2,500 restaurant bill stands out too, and
  // days 6 and 7 before today had nothing spent.
  assertEquals(habits.bigSpend?.title, 'Restaurant');
  assertEquals(habits.noSpendDays7, 2);
  assertEquals(habits.signals, [
    'large purchase: Restaurant',
    'week up on last week',
    'category jumped: Food',
    'saving well',
    'many small purchases',
    'repeat purchase: Restaurant',
    'no-spend days',
  ]);
});

Deno.test('habits: one purchase far above the usual is picked out', () => {
  const rows = [
    ...Array.from({ length: 10 }, (_, i) => spend(i + 2, 200)),
    spend(0, 5000, 'Phone repair', 'Other'),
  ];
  const habits = buildHabits(rows, NOW, NEPAL);
  assertEquals(habits.bigSpend, {
    title: 'Phone repair',
    amount: 5000,
    timesTypical: 25,
  });
  assertEquals(habits.signals[0], 'large purchase: Phone repair');
  // Not with too little history to know what is usual.
  assertEquals(buildHabits([spend(0, 5000)], NOW, NEPAL).bigSpend, null);
});

Deno.test('habits: nothing recorded gives zeros, not guesses', () => {
  const habits = buildHabits([], NOW, NEPAL);
  assertEquals(habits.today, { spent: 0, count: 0, biggest: null });
  assertEquals(habits.typicalDay, 0);
  assertEquals(habits.typicalUsedPct, null);
  assertEquals(habits.week.changePct, null);
  assertEquals(habits.signals, []);
});

// --- grounding ---------------------------------------------------------------

const SUMMARY = {
  currency: 'NPR',
  habits: {
    today: { spent: 420, count: 2, biggest: { title: 'Lunch at Shop 21', amount: 300 } },
    yesterday: { spent: 1250.5 },
    typicalDay: 250,
    typicalUsedPct: 168,
    week: { spent: 7040, previous: 2000, changePct: 252 },
    repeats: [{ title: 'Tea', count: 9, total: 540 }],
  },
};

Deno.test('grounding: figures from the data pass, in the forms people write them', () => {
  const ok = [
    'Good morning. You spent NPR 1,250 yesterday.',
    'You have used 168% of a typical day: NPR 420 of about NPR 250.',
    'This week NPR 7,040 against NPR 2,000 last week, up 252%.',
    'Tea 9 times in 30 days, NPR 540 in all.',
    'About 7k this week.',
    'Lunch at Shop 21 was the biggest, NPR 300.',
    'Nothing spent in the last 7 days.',
  ];
  for (const text of ok) {
    assertEquals(ungroundedNumbers(text, SUMMARY), [], text);
  }
});

Deno.test('grounding: a figure from nowhere is caught', () => {
  assertEquals(
    ungroundedNumbers('You spent NPR 3,400 on coffee this week.', SUMMARY),
    ['NPR 3,400'],
  );
  assertEquals(
    ungroundedNumbers('Spending is up 45% on last week.', SUMMARY),
    ['45%'],
  );
  // Even a small one, when it is money.
  assertEquals(ungroundedNumbers('Only Rs 15 left.', SUMMARY), ['Rs 15']);
  // And a count that is not a generic span and not in the data.
  assertEquals(ungroundedNumbers('You bought it 23 times.', SUMMARY), ['23']);
});

Deno.test('grounding: reads amounts, percentages and abbreviations', () => {
  assertEquals(
    quotedNumbers('NPR 1,250.50 is 12% of 3k, over 7 days').map((q) => [
      q.value,
      q.strict,
    ]),
    [[1250.5, true], [12, true], [3000, true], [7, false]],
  );
});

// --- the reply as a whole --------------------------------------------------

const reply = (fields: Record<string, unknown>) =>
  JSON.stringify({
    title: 'A warmer week',
    message: 'This week NPR 7,040 against NPR 2,000 last week.',
    category: 'spending',
    priority: 'high',
    action: 'Where did it go?',
    tone: 'roast',
    mood: 'roasting',
    ...fields,
  });

Deno.test('validateInsight: a grounded reply comes through with its tone and face', () => {
  const insight = validateInsight(reply({}), PROMPT_VERSION, {
    allowedTone: 'roast',
    grounding: [SUMMARY],
    kind: 'weekly',
  });
  assertEquals(insight.tone, 'roast');
  assertEquals(insight.mood, 'roasting');
  assertEquals(insight.kind, 'weekly');
  assertEquals(insight.promptVersion, 'finance-insight-v2');
});

Deno.test('validateInsight: never more playful than was allowed', () => {
  const playful = validateInsight(reply({}), PROMPT_VERSION, {
    allowedTone: 'playful',
    grounding: [SUMMARY],
  });
  assertEquals(playful.tone, 'playful');
  assertEquals(playful.mood, 'teasing');

  const normal = validateInsight(reply({}), PROMPT_VERSION, {
    grounding: [SUMMARY],
  });
  assertEquals(normal.tone, 'normal');
  assertEquals(normal.mood, 'curious');
});

Deno.test('validateInsight: an invented figure throws the reply away', () => {
  assertThrows(
    () =>
      validateInsight(
        reply({ message: 'You spent NPR 9,999 on tea this week.' }),
        PROMPT_VERSION,
        { allowedTone: 'roast', grounding: [SUMMARY] },
      ),
    Error,
    'not in the user\'s data',
  );
  assertThrows(() => validateInsight('not json', PROMPT_VERSION), Error);
  assertThrows(
    () => validateInsight(reply({ message: '' }), PROMPT_VERSION),
    Error,
  );
});

Deno.test('validateInsight: unknown values fall back to safe ones', () => {
  const insight = validateInsight(
    reply({ mood: 'furious', category: 'gossip', priority: 'urgent', tone: 'savage' }),
    PROMPT_VERSION,
    { allowedTone: 'roast', grounding: [SUMMARY] },
  );
  assertEquals(
    [insight.mood, insight.category, insight.priority, insight.tone],
    ['neutral', 'general', 'low', 'normal'],
  );
});

Deno.test('prompt: says what the moment is and forbids invented figures', () => {
  const user = buildInsightUserPrompt(SUMMARY, {
    kind: 'morning',
    tone: 'playful',
    avoid: ['A warmer week'],
  });
  assertEquals(user.includes('"kind":"morning"'), true);
  assertEquals(user.includes('"typicalUsedPct":168'), true);
  for (const kind of ['morning', 'midday', 'evening', 'endOfDay', 'weekly', 'monthly']) {
    assertEquals(INSIGHT_SYSTEM_PROMPT.includes(kind), true, kind);
  }
  assertEquals(INSIGHT_SYSTEM_PROMPT.includes('NEVER invent'), true);
  assertEquals(INSIGHT_SYSTEM_PROMPT.includes('never the person'), true);
});
