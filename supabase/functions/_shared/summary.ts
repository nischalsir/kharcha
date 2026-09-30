// Compact, user-scoped financial summary used as the ONLY financial context
// handed to the AI model. Never export raw rows or private fields (no notes,
// no attachment paths, no payment identifiers beyond a method label).
//
// This module is intentionally framework-free so the same aggregation can be
// reused by future notification workers (e.g. an FCM sender) without change.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

export interface CategorySpend {
  name: string;
  amount: number;
}

export interface FinancialSummary {
  currency: string;
  generatedAt: string;
  windowDays: number;
  totals: {
    expenseThisWindow: number;
    expensePreviousWindow: number;
    expenseChangePct: number | null;
    incomeThisWindow: number;
    balanceAllTime: number;
  };
  categories: CategorySpend[];
  topMerchants: CategorySpend[];
  budget: {
    monthlyTotal: number;
    spentThisWindow: number;
    usedPct: number | null;
  };
  recurring: { activeCount: number; upcomingCount: number };
  dailyExpense: { date: string; amount: number }[];
  streak: { activeDays: number; lastExpenseAt: string | null };
  hasEnoughData: boolean;
}

const DAY = 24 * 60 * 60 * 1000;

function isoDay(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function round(value: number): number {
  return Math.round(value * 100) / 100;
}

/**
 * Builds a compact summary for one user.
 *
 * @param supabase A Supabase client constructed with the caller's JWT so every
 *   query is constrained by row level security. This function never receives a
 *   service-role key, so it cannot read another user's rows.
 * @param options.windowDays Size of the comparison window.
 * @param options.userId Explicit user to scope to. REQUIRED when `supabase` is
 *   a service-role client, because that client bypasses RLS and would
 *   otherwise return every user's rows. Supplying it adds a `user_id` filter to
 *   every query, so the worker never has to trust a shared connection to be
 *   implicitly scoped.
 */
export async function buildFinancialSummary(
  supabase: SupabaseClient,
  options: { windowDays?: number; userId?: string } = {},
): Promise<FinancialSummary> {
  const windowDays = options.windowDays ?? 30;
  const now = new Date();
  const windowStart = new Date(now.getTime() - windowDays * DAY);
  const previousStart = new Date(now.getTime() - 2 * windowDays * DAY);
  const lookbackStart = previousStart.toISOString();

  // `user_id` filters are applied to every table, whether or not the caller
  // needs them: with a user JWT this is redundant with RLS, and with a
  // service-role key it is the only thing preventing a cross-user leak.
  //
  // The query type is kept opaque (T is never inspected) because naming
  // PostgrestFilterBuilder here makes TypeScript instantiate a chain several
  // generic levels deep and give up with "excessively deep and possibly
  // infinite".
  const scoped = <T>(query: T, userId: string | undefined): T =>
    userId
      ? (query as unknown as { eq: (column: string, value: string) => T }).eq(
        "user_id",
        userId,
      )
      : query;

  const [transactions, budgets, categories, recurring] = await Promise.all([
    scoped(
      supabase
        .from("transactions")
        .select("amount,type,category_id,occurred_at,title")
        .is("deleted_at", null)
        .gte("occurred_at", lookbackStart),
      options.userId,
    ),
    scoped(
      supabase.from("budgets").select("amount,category_id").is(
        "deleted_at",
        null,
      ),
      options.userId,
    ),
    scoped(
      supabase.from("categories").select("id,name").is("deleted_at", null),
      options.userId,
    ),
    scoped(
      supabase
        .from("recurring_transactions")
        .select("id,is_active,next_date")
        .is("deleted_at", null),
      options.userId,
    ),
  ]);

  const rows = (transactions.data ?? []) as Array<Record<string, unknown>>;
  const budgetRows = (budgets.data ?? []) as Array<Record<string, unknown>>;
  const categoryRows = (categories.data ?? []) as Array<
    Record<string, unknown>
  >;
  const recurringRows = (recurring.data ?? []) as Array<
    Record<string, unknown>
  >;

  const categoryName = new Map<string, string>();
  for (const row of categoryRows) {
    if (typeof row.id === "string" && typeof row.name === "string") {
      categoryName.set(row.id, row.name);
    }
  }

  const startMs = windowStart.getTime();
  const prevMs = previousStart.getTime();

  let expenseThis = 0;
  let expensePrev = 0;
  let incomeThis = 0;
  let balanceAllTime = 0;
  const byCategory = new Map<string, number>();
  const byMerchant = new Map<string, number>();
  const byDay = new Map<string, number>();
  const activeDays = new Set<string>();
  let lastExpenseAt: string | null = null;

  for (const row of rows) {
    const amount = Number(row.amount) || 0;
    const type = String(row.type ?? "expense");
    const occurred = String(row.occurred_at ?? "");
    const at = new Date(occurred).getTime();
    if (!Number.isFinite(at)) continue;

    if (type === "income") {
      balanceAllTime += amount;
      if (at >= startMs) incomeThis += amount;
    } else if (type === "expense") {
      balanceAllTime -= amount;
    }

    if (type !== "expense") continue;
    if (at >= startMs) {
      expenseThis += amount;
      activeDays.add(isoDay(new Date(at)));
      if (!lastExpenseAt || occurred > lastExpenseAt) lastExpenseAt = occurred;
      const day = isoDay(new Date(at));
      byDay.set(day, (byDay.get(day) ?? 0) + amount);
      const catId = typeof row.category_id === "string" ? row.category_id : "";
      const catLabel = catId
        ? categoryName.get(catId) ?? "Uncategorised"
        : "Uncategorised";
      byCategory.set(catLabel, (byCategory.get(catLabel) ?? 0) + amount);
      const title = String(row.title ?? "").trim();
      if (title) byMerchant.set(title, (byMerchant.get(title) ?? 0) + amount);
    } else if (at >= prevMs) {
      expensePrev += amount;
    }
  }

  const budgetTotal = budgetRows.reduce(
    (sum, row) => sum + (Number(row.amount) || 0),
    0,
  );

  const toSorted = (map: Map<string, number>): CategorySpend[] =>
    [...map.entries()]
      .map(([name, amount]) => ({ name, amount: round(amount) }))
      .sort((a, b) => b.amount - a.amount)
      .slice(0, 8);

  const changePct = expensePrev > 0
    ? round(((expenseThis - expensePrev) / expensePrev) * 100)
    : null;

  const dailyExpense = [...byDay.entries()]
    .map(([date, amount]) => ({ date, amount: round(amount) }))
    .sort((a, b) => a.date.localeCompare(b.date))
    .slice(-14);

  const upcoming = recurringRows.filter((row) =>
    typeof row.next_date === "string" && new Date(row.next_date as string) > now
  );

  return {
    currency: "NPR",
    generatedAt: now.toISOString(),
    windowDays,
    totals: {
      expenseThisWindow: round(expenseThis),
      expensePreviousWindow: round(expensePrev),
      expenseChangePct: changePct,
      incomeThisWindow: round(incomeThis),
      balanceAllTime: round(balanceAllTime),
    },
    categories: toSorted(byCategory),
    topMerchants: toSorted(byMerchant).slice(0, 6),
    budget: {
      monthlyTotal: round(budgetTotal),
      spentThisWindow: round(expenseThis),
      usedPct: budgetTotal > 0
        ? round((expenseThis / budgetTotal) * 100)
        : null,
    },
    recurring: {
      activeCount:
        recurringRows.filter((row) => row.is_active !== false).length,
      upcomingCount: upcoming.length,
    },
    dailyExpense,
    streak: { activeDays: activeDays.size, lastExpenseAt },
    hasEnoughData: rows.length >= 5,
  };
}
