// What a user's own records say about how they spend: the figures a
// time-aware suggestion talks about, and the habits that stand out.
//
// Pure: it is given rows and a clock, reads nothing itself, and can be tested
// with plain arrays. It mirrors `SpendingHabitAnalyzer` in the app
// (lib/services/spending_habits.dart), which writes the same kind of
// suggestion on the device; the two use the same windows and thresholds so
// they do not contradict each other.

export interface HabitRow {
  amount: number;
  type: string;
  /** ISO timestamp. */
  occurred_at: string;
  title: string;
  /** Already resolved to a name; `Uncategorised` when there is none. */
  category: string;
}

export interface Habits {
  /** The user's own calendar day, `YYYY-MM-DD`. */
  localDate: string;
  today: {
    spent: number;
    count: number;
    biggest: { title: string; amount: number } | null;
  };
  yesterday: { spent: number; count: number };
  /** Average spending per day over the 30 days before today. */
  typicalDay: number;
  /** How much of a typical day today has used, in percent. */
  typicalUsedPct: number | null;
  /** The last 7 days including today, against the 7 days before them. */
  week: { spent: number; previous: number; changePct: number | null };
  /** The last 30 days. Not a calendar month. */
  last30Days: {
    spent: number;
    income: number;
    saved: number;
    savedPct: number | null;
  };
  /** Categories that moved most this week against last. */
  categoryMovers: {
    name: string;
    thisWeek: number;
    lastWeek: number;
    changePct: number | null;
  }[];
  /** The same purchase made three times or more in 30 days. */
  repeats: { title: string; count: number; total: number }[];
  /** Purchases at or under `limit` in the last 7 days. */
  smallPurchases: { limit: number; count: number; total: number };
  /** One purchase since yesterday far above the user's usual one. */
  bigSpend: { title: string; amount: number; timesTypical: number } | null;
  /** Days with nothing spent, out of the 7 before today. */
  noSpendDays7: number;
  /** What stands out, most notable first. */
  signals: string[];
}

export const SMALL_PURCHASE_LIMIT = 250;
const DAY = 24 * 60 * 60 * 1000;

function round(value: number): number {
  return Math.round(value * 100) / 100;
}

/**
 * The calendar day a moment falls on for someone [offsetMinutes] ahead of
 * UTC, as a count of days. Nepal is 345 minutes ahead: at 02:00 there it is
 * already tomorrow while UTC is still on today, and a purchase made then
 * belongs to the user's new day.
 */
function dayIndex(ms: number, offsetMinutes: number): number {
  return Math.floor((ms + offsetMinutes * 60_000) / DAY);
}

function dayLabel(index: number): string {
  return new Date(index * DAY).toISOString().slice(0, 10);
}

export function buildHabits(
  rows: HabitRow[],
  now: Date,
  offsetMinutes = 345,
): Habits {
  const today = dayIndex(now.getTime(), offsetMinutes);
  const weekStart = today - 6;
  const lastWeekStart = today - 13;
  const windowStart = today - 30;

  let spentToday = 0;
  let countToday = 0;
  let biggestToday: { title: string; amount: number } | null = null;
  let spentYesterday = 0;
  let countYesterday = 0;
  let week = 0;
  let lastWeek = 0;
  let spent30 = 0;
  let income30 = 0;
  let spentBefore = 0;
  let earliest: number | null = null;
  let smallCount = 0;
  let smallTotal = 0;
  let largest: { title: string; amount: number } | null = null;

  const weekByCategory = new Map<string, number>();
  const lastWeekByCategory = new Map<string, number>();
  const amounts: number[] = [];
  const repeats = new Map<string, { title: string; count: number; total: number }>();
  const spendDays = new Set<number>();

  for (const row of rows) {
    const amount = Number(row.amount) || 0;
    const at = new Date(row.occurred_at).getTime();
    if (!Number.isFinite(at) || amount <= 0) continue;
    const day = dayIndex(at, offsetMinutes);
    if (day > today) continue;

    if (row.type === 'income') {
      if (day >= windowStart) income30 += amount;
      continue;
    }
    if (row.type !== 'expense') continue;

    const title = String(row.title ?? '').trim();
    if (day === today) {
      spentToday += amount;
      countToday++;
      if (!biggestToday || amount > biggestToday.amount) {
        biggestToday = { title, amount: round(amount) };
      }
    } else if (day === today - 1) {
      spentYesterday += amount;
      countYesterday++;
    }

    if (day >= weekStart) {
      week += amount;
      weekByCategory.set(row.category, (weekByCategory.get(row.category) ?? 0) + amount);
      if (amount <= SMALL_PURCHASE_LIMIT) {
        smallCount++;
        smallTotal += amount;
      }
    } else if (day >= lastWeekStart) {
      lastWeek += amount;
      lastWeekByCategory.set(
        row.category,
        (lastWeekByCategory.get(row.category) ?? 0) + amount,
      );
    }

    if (day >= windowStart) {
      spent30 += amount;
      amounts.push(amount);
      spendDays.add(day);
      if (day !== today) {
        spentBefore += amount;
        if (earliest === null || day < earliest) earliest = day;
      }
      const key = title.toLowerCase();
      if (key) {
        const seen = repeats.get(key);
        repeats.set(key, {
          title: seen?.title ?? title,
          count: (seen?.count ?? 0) + 1,
          total: (seen?.total ?? 0) + amount,
        });
      }
      if (day >= today - 1 && (!largest || amount > largest.amount)) {
        largest = { title, amount };
      }
    }
  }

  const span = earliest === null ? 0 : Math.min(30, Math.max(1, today - earliest));
  const typicalDay = span === 0 ? 0 : spentBefore / span;

  const movers = [...weekByCategory.entries()]
    .map(([name, thisWeek]) => {
      const before = lastWeekByCategory.get(name) ?? 0;
      return {
        name,
        thisWeek: round(thisWeek),
        lastWeek: round(before),
        changePct: before > 0 ? round(((thisWeek - before) / before) * 100) : null,
        by: thisWeek - before,
      };
    })
    .filter((m) => m.thisWeek >= 500)
    .sort((a, b) => b.by - a.by)
    .slice(0, 3)
    .map(({ by: _by, ...rest }) => rest);

  const repeated = [...repeats.values()]
    .filter((r) => r.count >= 3)
    .sort((a, b) => b.total - a.total)
    .slice(0, 3)
    .map((r) => ({ ...r, total: round(r.total) }));

  let bigSpend: Habits['bigSpend'] = null;
  if (largest && amounts.length >= 8) {
    const sorted = [...amounts].sort((a, b) => a - b);
    const median = sorted[Math.floor(sorted.length / 2)];
    if (median > 0 && largest.amount >= 1000 && largest.amount >= median * 3) {
      bigSpend = {
        title: largest.title,
        amount: round(largest.amount),
        timesTypical: Math.round(largest.amount / median),
      };
    }
  }

  let quiet = 0;
  if (earliest !== null && earliest <= weekStart) {
    for (let i = 1; i <= 7; i++) if (!spendDays.has(today - i)) quiet++;
  }

  const weekChange = lastWeek > 0 ? ((week - lastWeek) / lastWeek) * 100 : null;
  const saved = income30 - spent30;

  // What stands out, in the order the app ranks it.
  const signals: string[] = [];
  if (income30 > 0 && saved < 0) signals.push('spending above income');
  if (bigSpend) signals.push(`large purchase: ${bigSpend.title}`);
  if (lastWeek >= 500 && weekChange !== null && weekChange >= 25) {
    signals.push('week up on last week');
  }
  const surge = movers.find((m) =>
    m.lastWeek <= 0 ? m.thisWeek >= 1500 : (m.changePct ?? 0) >= 40
  );
  if (surge) signals.push(`category jumped: ${surge.name}`);
  if (income30 > 0 && saved >= income30 * 0.2) signals.push('saving well');
  if (lastWeek >= 500 && weekChange !== null && weekChange <= -15) {
    signals.push('week down on last week');
  }
  if (smallCount >= 8) signals.push('many small purchases');
  if (repeated.some((r) => r.count >= 4)) {
    signals.push(`repeat purchase: ${repeated.find((r) => r.count >= 4)!.title}`);
  }
  if (quiet >= 2) signals.push('no-spend days');

  return {
    localDate: dayLabel(today),
    today: {
      spent: round(spentToday),
      count: countToday,
      biggest: biggestToday,
    },
    yesterday: { spent: round(spentYesterday), count: countYesterday },
    typicalDay: round(typicalDay),
    typicalUsedPct: typicalDay > 0 ? Math.round((spentToday / typicalDay) * 100) : null,
    week: {
      spent: round(week),
      previous: round(lastWeek),
      changePct: weekChange === null ? null : Math.round(weekChange),
    },
    last30Days: {
      spent: round(spent30),
      income: round(income30),
      saved: round(saved),
      savedPct: income30 > 0 ? Math.round((saved / income30) * 100) : null,
    },
    categoryMovers: movers,
    repeats: repeated,
    smallPurchases: {
      limit: SMALL_PURCHASE_LIMIT,
      count: smallCount,
      total: round(smallTotal),
    },
    bigSpend,
    noSpendDays7: quiet,
    signals,
  };
}
