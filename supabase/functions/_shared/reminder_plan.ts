// Decides which data-driven reminders are due for one user right now.
//
// Pure: the push-reminders worker loads the rows and the user's local time,
// this module turns them into notifications, and the worker sends them. Every
// notification carries one dedupe key per underlying item (a budget level, a
// bill's due date, an overdue week...), and items whose key was already sent
// are dropped here, so a run that repeats within the same hour sends nothing.
//
// When each category fires, in the user's local time:
//   budget_warnings        08:00-21:59, within the hour a budget crosses 80% / 100%
//   recurring_reminders    reminder hour (default 09), bills due today/tomorrow
//   friend_debt_reminders  reminder hour, friend debts due today/tomorrow
//   overdue_reminders      reminder hour, past-due friend/pasal credits, at most
//                          once a week each, for up to eight weeks
//   pasal_month_end        reminder hour on the second-to-last day of the BS
//                          month, for pasals with an unpaid balance
//   weekly_summary         reminder hour on Sunday (the Nepali week start)
//   monthly_report         reminder hour on the first day of a BS month: what
//                          the month that just ended came to
//   daily_summary          summary hour (default 21)
import {
  addDays,
  BS_MONTH_NAMES,
  bsMonthRange,
  daysBetween,
  daysInBsMonth,
  toBs,
} from "./bs_calendar.ts";

export type ReminderCategory =
  | "budget_warnings"
  | "recurring_reminders"
  | "friend_debt_reminders"
  | "overdue_reminders"
  | "pasal_month_end"
  | "daily_summary"
  | "weekly_summary"
  | "monthly_report";

/** Mirrors `defaultEnabled` in lib/models/push_category.dart. */
export const REMINDER_DEFAULTS: Record<ReminderCategory, boolean> = {
  budget_warnings: true,
  recurring_reminders: true,
  friend_debt_reminders: true,
  overdue_reminders: true,
  pasal_month_end: true,
  daily_summary: false,
  weekly_summary: false,
  monthly_report: true,
};

export const DEFAULT_REMINDER_HOUR = 9;
export const DEFAULT_SUMMARY_HOUR = 21;
const BUDGET_START_HOUR = 8;
const BUDGET_END_HOUR = 22;
const MAX_OVERDUE_WEEKS = 8;
const MAX_BODY = 380;

export interface BudgetRow {
  id: string;
  category_id: string | null;
  period: string;
  amount: number;
  bs_year: number | null;
  bs_month: number | null;
  week_start: string | null;
}

export interface TransactionRow {
  type: string;
  amount: number;
  category_id: string | null;
  occurred_at: string;
}

export interface RecurringRow {
  id: string;
  title: string;
  amount: number;
  type: string;
  next_date: string;
  end_date: string | null;
  is_active: boolean;
}

export interface FriendCreditRow {
  id: string;
  friend_id: string;
  direction: string;
  title: string | null;
  remaining_amount: number;
  status: string;
  due_date: string | null;
}

export interface PasalCreditRow {
  id: string;
  pasal_id: string;
  title: string | null;
  remaining_amount: number;
  status: string;
  due_date: string | null;
}

export interface ReminderInput {
  /** The user's local wall clock. */
  local: { date: string; hour: number };
  utcOffsetMinutes: number;
  prefs: Record<string, unknown> | null;
  currency: string;
  /** Dedupe keys already delivered to this user. */
  sentKeys: Set<string>;
  budgets: BudgetRow[];
  /** Completed, non-deleted transactions from at least the last 40 days. */
  transactions: TransactionRow[];
  recurring: RecurringRow[];
  friendCredits: FriendCreditRow[];
  pasalCredits: PasalCreditRow[];
  categoryNames: Map<string, string>;
  friendNames: Map<string, string>;
  pasalNames: Map<string, string>;
}

export interface PlannedPush {
  category: ReminderCategory;
  /** Every key this push covers; all are logged when it is sent. */
  keys: string[];
  title: string;
  body: string;
  route: string;
  /** JSON-encoded single route argument, as PushMessage.routeArgs expects. */
  routeArgs?: string;
}

// ------------------------------------------------------------------ helpers

export function isEnabled(
  prefs: Record<string, unknown> | null,
  category: ReminderCategory,
): boolean {
  const value = prefs?.[category];
  return typeof value === "boolean" ? value : REMINDER_DEFAULTS[category];
}

function hourPref(
  prefs: Record<string, unknown> | null,
  key: string,
  fallback: number,
): number {
  const value = prefs?.[key];
  return typeof value === "number" && Number.isInteger(value) && value >= 0 &&
      value <= 23
    ? value
    : fallback;
}

/** Indian digit grouping, matching CurrencyFormatter in the app. */
export function formatMoney(amount: number, currency: string): string {
  const rounded = Math.round(Math.abs(amount));
  const digits = String(rounded);
  let grouped = digits;
  if (digits.length > 3) {
    const last = digits.slice(-3);
    let rest = digits.slice(0, -3);
    const parts: string[] = [];
    while (rest.length > 2) {
      parts.unshift(rest.slice(-2));
      rest = rest.slice(0, -2);
    }
    if (rest) parts.unshift(rest);
    grouped = `${parts.join(",")},${last}`;
  }
  const sign = amount < 0 && rounded !== 0 ? "-" : "";
  return `${sign}${currency || "NPR"} ${grouped}`;
}

/** Local calendar date of an instant, for a device offset east of UTC. */
export function localDateOf(instant: string, utcOffsetMinutes: number): string {
  const ms = Date.parse(instant);
  return new Date(ms + utcOffsetMinutes * 60_000).toISOString().slice(0, 10);
}

function plural(count: number, one: string, many: string): string {
  return `${count} ${count === 1 ? one : many}`;
}

function clip(text: string): string {
  return text.length > MAX_BODY ? `${text.slice(0, MAX_BODY - 1)}…` : text;
}

function whenLabel(due: string, today: string): string {
  return due === today ? "today" : "tomorrow";
}

interface Item {
  key: string;
  line: string;
  route: string;
  routeArgs?: string;
}

/**
 * One notification for one new item, or one summary notification listing
 * several, so a busy morning is a single buzz rather than five.
 */
function group(
  category: ReminderCategory,
  items: Item[],
  single: (item: Item) => { title: string; body: string },
  manyTitle: (count: number) => string,
  manyRoute: string,
): PlannedPush[] {
  if (items.length === 0) return [];
  if (items.length === 1) {
    const [item] = items;
    const { title, body } = single(item);
    return [{
      category,
      keys: [item.key],
      title,
      body: clip(body),
      route: item.route,
      routeArgs: item.routeArgs,
    }];
  }
  return [{
    category,
    keys: items.map((item) => item.key),
    title: manyTitle(items.length),
    body: clip(items.map((item) => `• ${item.line}`).join("\n")),
    route: manyRoute,
  }];
}

// --------------------------------------------------------------- categories

function budgetWarnings(input: ReminderInput): PlannedPush[] {
  const today = input.local.date;
  const bsToday = toBs(today);
  const out: PlannedPush[] = [];

  for (const budget of input.budgets) {
    const amount = Number(budget.amount);
    if (!(amount > 0)) continue;

    let range: { start: string; end: string } | null = null;
    let scope: string;
    if (budget.period === "weekly") {
      if (!budget.week_start) continue;
      const end = addDays(budget.week_start, 7);
      if (today < budget.week_start || today >= end) continue;
      range = { start: budget.week_start, end };
      scope = "weekly";
    } else {
      if (!bsToday) continue;
      if (budget.bs_year !== bsToday.year || budget.bs_month !== bsToday.month) {
        continue;
      }
      range = bsMonthRange(bsToday.year, bsToday.month);
      scope = BS_MONTH_NAMES[bsToday.month - 1];
    }
    if (!range) continue;

    let spent = 0;
    for (const tx of input.transactions) {
      if (tx.type !== "expense") continue;
      if (budget.category_id && tx.category_id !== budget.category_id) continue;
      const day = localDateOf(tx.occurred_at, input.utcOffsetMinutes);
      if (day >= range.start && day < range.end) spent += Number(tx.amount);
    }

    const ratio = spent / amount;
    const level = ratio >= 1 ? 100 : ratio >= 0.8 ? 80 : null;
    if (level === null) continue;
    const key = `budget:${budget.id}:${range.start}:${level}`;
    // Never step back down to the 80% notice after the 100% one went out.
    const overKey = `budget:${budget.id}:${range.start}:100`;
    if (input.sentKeys.has(key) || input.sentKeys.has(overKey)) continue;

    const categoryName = budget.category_id
      ? input.categoryNames.get(budget.category_id)
      : undefined;
    const label = categoryName
      ? `${categoryName} budget`
      : `${scope} budget`;
    const money = (value: number) => formatMoney(value, input.currency);
    const daysLeft = daysBetween(today, range.end);

    out.push(
      level === 100
        ? {
          category: "budget_warnings",
          keys: [key],
          title: "🚨 Over budget",
          body: clip(
            `You've spent ${money(spent)} of your ${money(amount)} ${label}, ` +
              `${money(spent - amount)} over.`,
          ),
          route: "/budgets",
        }
        : {
          category: "budget_warnings",
          keys: [key],
          title: "⚠️ Budget alert",
          body: clip(
            `You've used ${Math.floor(ratio * 100)}% of your ${label} ` +
              `(${money(spent)} of ${money(amount)}). ${money(amount - spent)} ` +
              `left for ${plural(daysLeft, "day", "days")}.`,
          ),
          route: "/budgets",
        },
    );
  }
  return out;
}

function recurringReminders(input: ReminderInput): PlannedPush[] {
  const today = input.local.date;
  const tomorrow = addDays(today, 1);
  const items: Item[] = [];
  for (const row of input.recurring) {
    if (!row.is_active || row.type !== "expense") continue;
    if (row.next_date !== today && row.next_date !== tomorrow) continue;
    if (row.end_date && row.end_date < row.next_date) continue;
    const key = `recurring:${row.id}:${row.next_date}`;
    if (input.sentKeys.has(key)) continue;
    const when = whenLabel(row.next_date, today);
    items.push({
      key,
      line: `${row.title}: ${formatMoney(row.amount, input.currency)} due ${when}`,
      route: "/payments",
    });
  }
  return group(
    "recurring_reminders",
    items,
    (item) => ({ title: "📅 Upcoming payment", body: `${item.line}.` }),
    (count) => `📅 ${count} payments due soon`,
    "/payments",
  );
}

function friendLine(
  row: FriendCreditRow,
  name: string,
  money: string,
  suffix: string,
): string {
  const what = row.title ? ` for ${row.title}` : "";
  return row.direction === "I_OWE"
    ? `You owe ${name} ${money}${what}, ${suffix}`
    : `${name} owes you ${money}${what}, ${suffix}`;
}

function isOpen(status: string, remaining: number): boolean {
  return status !== "paid" && Number(remaining) > 0;
}

function friendDebtReminders(input: ReminderInput): PlannedPush[] {
  const today = input.local.date;
  const tomorrow = addDays(today, 1);
  const items: Item[] = [];
  for (const row of input.friendCredits) {
    if (!isOpen(row.status, row.remaining_amount) || !row.due_date) continue;
    if (row.due_date !== today && row.due_date !== tomorrow) continue;
    const key = `friend:${row.id}:${row.due_date}`;
    if (input.sentKeys.has(key)) continue;
    const name = input.friendNames.get(row.friend_id) ?? "A friend";
    items.push({
      key,
      line: friendLine(
        row,
        name,
        formatMoney(row.remaining_amount, input.currency),
        `due ${whenLabel(row.due_date, today)}`,
      ),
      route: "/friends/detail",
      routeArgs: JSON.stringify(row.friend_id),
    });
  }
  return group(
    "friend_debt_reminders",
    items,
    (item) => ({ title: "🤝 Friend reminder", body: `${item.line}.` }),
    (count) => `🤝 ${count} friend payments due`,
    "/friends",
  );
}

function overdueReminders(input: ReminderInput): PlannedPush[] {
  const today = input.local.date;
  const items: Item[] = [];

  const consider = (
    keyPrefix: string,
    due: string | null,
    open: boolean,
    build: (days: number) => Omit<Item, "key">,
  ) => {
    if (!open || !due || due >= today) return;
    const days = daysBetween(due, today);
    const week = Math.floor((days - 1) / 7);
    if (week >= MAX_OVERDUE_WEEKS) return;
    const key = `${keyPrefix}:${week}`;
    if (input.sentKeys.has(key)) return;
    items.push({ key, ...build(days) });
  };

  for (const row of input.friendCredits) {
    consider(
      `overdue:friend:${row.id}`,
      row.due_date,
      isOpen(row.status, row.remaining_amount),
      (days) => ({
        line: friendLine(
          row,
          input.friendNames.get(row.friend_id) ?? "A friend",
          formatMoney(row.remaining_amount, input.currency),
          `${plural(days, "day", "days")} overdue`,
        ),
        route: "/friends/detail",
        routeArgs: JSON.stringify(row.friend_id),
      }),
    );
  }
  for (const row of input.pasalCredits) {
    consider(
      `overdue:pasal:${row.id}`,
      row.due_date,
      isOpen(row.status, row.remaining_amount),
      (days) => {
        const pasal = input.pasalNames.get(row.pasal_id) ?? "A pasal";
        const what = row.title ? ` for ${row.title}` : "";
        return {
          line: `${pasal}: ${
            formatMoney(row.remaining_amount, input.currency)
          }${what}, ${plural(days, "day", "days")} overdue`,
          route: "/pasal/detail",
          routeArgs: JSON.stringify(row.pasal_id),
        };
      },
    );
  }

  const allFriends = items.every((item) => item.route === "/friends/detail");
  const allPasals = items.every((item) => item.route === "/pasal/detail");
  return group(
    "overdue_reminders",
    items,
    (item) => ({ title: "⏰ Payment overdue", body: `${item.line}.` }),
    (count) => `⏰ ${count} overdue payments`,
    allFriends ? "/friends" : allPasals ? "/pasal" : "/",
  );
}

function pasalMonthEnd(input: ReminderInput): PlannedPush[] {
  const bs = toBs(input.local.date);
  if (!bs) return [];
  // Second-to-last day, so there is still a full day to settle up.
  if (bs.day !== daysInBsMonth(bs.year, bs.month) - 1) return [];
  const month = BS_MONTH_NAMES[bs.month - 1];

  const owed = new Map<string, number>();
  for (const row of input.pasalCredits) {
    if (!isOpen(row.status, row.remaining_amount)) continue;
    owed.set(row.pasal_id, (owed.get(row.pasal_id) ?? 0) + Number(row.remaining_amount));
  }

  const items: Item[] = [];
  for (const [pasalId, total] of owed) {
    if (!input.pasalNames.has(pasalId)) continue; // inactive or deleted pasal
    const key = `pasal-month:${pasalId}:${bs.year}-${bs.month}`;
    if (input.sentKeys.has(key)) continue;
    items.push({
      key,
      line: `${input.pasalNames.get(pasalId)}: ${
        formatMoney(total, input.currency)
      } still due`,
      route: "/pasal/detail",
      routeArgs: JSON.stringify(pasalId),
    });
  }
  return group(
    "pasal_month_end",
    items,
    (item) => ({
      title: `🏪 ${month} ends tomorrow`,
      body: `${item.line}. Settle up before the new month.`,
    }),
    () => `🏪 ${month} ends tomorrow`,
    "/pasal",
  );
}

function totals(
  input: ReminderInput,
  start: string,
  end: string,
): { spent: number; earned: number; count: number; top: string | null } {
  let spent = 0;
  let earned = 0;
  let count = 0;
  const byCategory = new Map<string, number>();
  for (const tx of input.transactions) {
    const day = localDateOf(tx.occurred_at, input.utcOffsetMinutes);
    if (day < start || day >= end) continue;
    count += 1;
    const amount = Number(tx.amount);
    if (tx.type === "income") {
      earned += amount;
    } else if (tx.type === "expense") {
      spent += amount;
      if (tx.category_id) {
        byCategory.set(tx.category_id, (byCategory.get(tx.category_id) ?? 0) + amount);
      }
    }
  }
  let top: string | null = null;
  let best = 0;
  for (const [id, amount] of byCategory) {
    if (amount > best && input.categoryNames.has(id)) {
      best = amount;
      top = input.categoryNames.get(id)!;
    }
  }
  return { spent, earned, count, top };
}

function dailySummary(input: ReminderInput): PlannedPush[] {
  const today = input.local.date;
  const key = `daily:${today}`;
  if (input.sentKeys.has(key)) return [];
  const day = totals(input, today, addDays(today, 1));
  const money = (value: number) => formatMoney(value, input.currency);
  if (day.count === 0) {
    return [{
      category: "daily_summary",
      keys: [key],
      title: "📊 Your day in Kharcha",
      body: "Nothing logged today. Spent anything? Add it before you forget.",
      route: "/transactions/expense/add",
    }];
  }
  const parts = [`Spent ${money(day.spent)}`];
  if (day.earned > 0) parts.push(`earned ${money(day.earned)}`);
  let body = `${parts.join(", ")} across ${
    plural(day.count, "entry", "entries")
  }.`;
  if (day.top) body += ` Most went to ${day.top}.`;
  return [{
    category: "daily_summary",
    keys: [key],
    title: "📊 Your day in Kharcha",
    body: clip(body),
    route: "/reports",
  }];
}

function weeklySummary(input: ReminderInput): PlannedPush[] {
  const today = input.local.date;
  const key = `weekly:${today}`;
  if (input.sentKeys.has(key)) return [];
  const week = totals(input, addDays(today, -7), today);
  const before = totals(input, addDays(today, -14), addDays(today, -7));
  const money = (value: number) => formatMoney(value, input.currency);
  if (week.count === 0) {
    return [{
      category: "weekly_summary",
      keys: [key],
      title: "📈 Your week in Kharcha",
      body: "No entries last week. A fresh week starts today!",
      route: "/",
    }];
  }
  let body = `Last week you spent ${money(week.spent)}`;
  if (before.spent > 0) {
    const change = Math.round(((week.spent - before.spent) / before.spent) * 100);
    if (change !== 0) {
      body += `, ${Math.abs(change)}% ${change > 0 ? "more" : "less"} than the week before`;
    }
  }
  body += ".";
  if (week.earned > 0) body += ` Income: ${money(week.earned)}.`;
  if (week.top) body += ` Top category: ${week.top}.`;
  return [{
    category: "weekly_summary",
    keys: [key],
    title: "📈 Your week in Kharcha",
    body: clip(body),
    route: "/reports",
  }];
}

/**
 * On the first day of a Bikram Sambat month: what the month that just ended
 * came to, against the one before it. Says nothing when nothing was written
 * down that month; there is no report to give.
 */
function monthlyReport(input: ReminderInput): PlannedPush[] {
  const bs = toBs(input.local.date);
  if (!bs || bs.day !== 1) return [];
  const back = (year: number, month: number) =>
    month === 1 ? { year: year - 1, month: 12 } : { year, month: month - 1 };
  const last = back(bs.year, bs.month);
  const key = `monthly:${last.year}-${last.month}`;
  if (input.sentKeys.has(key)) return [];
  const range = bsMonthRange(last.year, last.month);
  if (!range) return [];
  const month = totals(input, range.start, range.end);
  if (month.count === 0) return [];

  const name = BS_MONTH_NAMES[last.month - 1];
  const money = (value: number) => formatMoney(value, input.currency);
  let body = `In ${name} you spent ${money(month.spent)}`;
  if (month.earned > 0) {
    const saved = month.earned - month.spent;
    body += ` and earned ${money(month.earned)}`;
    body += saved >= 0
      ? `, so ${money(saved)} was saved`
      : `, ${money(-saved)} more than came in`;
  }
  body += ".";
  const earlier = back(last.year, last.month);
  const earlierRange = bsMonthRange(earlier.year, earlier.month);
  const before = earlierRange
    ? totals(input, earlierRange.start, earlierRange.end)
    : null;
  if (before && before.spent > 0) {
    const change = Math.round(
      ((month.spent - before.spent) / before.spent) * 100,
    );
    if (change !== 0) {
      body += ` That is ${Math.abs(change)}% ${
        change > 0 ? "more" : "less"
      } than ${BS_MONTH_NAMES[earlier.month - 1]}.`;
    }
  }
  if (month.top) body += ` Most went to ${month.top}.`;
  return [{
    category: "monthly_report",
    keys: [key],
    title: `📅 Your ${name} report`,
    body: clip(body),
    route: "/reports",
    // Opens Reports on the month the report is about.
    routeArgs: JSON.stringify("last-month"),
  }];
}

// --------------------------------------------------------------------- plan

/** Hours at which anything at all could be due, so the worker can skip
 * loading data for users with nothing possible this run. */
export function couldBeDue(
  prefs: Record<string, unknown> | null,
  hour: number,
): boolean {
  if (
    isEnabled(prefs, "budget_warnings") && hour >= BUDGET_START_HOUR &&
    hour < BUDGET_END_HOUR
  ) {
    return true;
  }
  return hour === hourPref(prefs, "reminder_hour", DEFAULT_REMINDER_HOUR) ||
    hour === hourPref(prefs, "daily_summary_hour", DEFAULT_SUMMARY_HOUR);
}

export function planReminders(input: ReminderInput): PlannedPush[] {
  const { prefs, local } = input;
  const on = (category: ReminderCategory) => isEnabled(prefs, category);
  const reminderHour = hourPref(prefs, "reminder_hour", DEFAULT_REMINDER_HOUR);
  const summaryHour = hourPref(prefs, "daily_summary_hour", DEFAULT_SUMMARY_HOUR);
  const out: PlannedPush[] = [];

  if (
    on("budget_warnings") && local.hour >= BUDGET_START_HOUR &&
    local.hour < BUDGET_END_HOUR
  ) {
    out.push(...budgetWarnings(input));
  }
  if (local.hour === reminderHour) {
    if (on("recurring_reminders")) out.push(...recurringReminders(input));
    if (on("friend_debt_reminders")) out.push(...friendDebtReminders(input));
    if (on("overdue_reminders")) out.push(...overdueReminders(input));
    if (on("pasal_month_end")) out.push(...pasalMonthEnd(input));
    const sunday = new Date(`${local.date}T00:00:00Z`).getUTCDay() === 0;
    if (sunday && on("weekly_summary")) out.push(...weeklySummary(input));
    if (on("monthly_report")) out.push(...monthlyReport(input));
  }
  if (local.hour === summaryHour && on("daily_summary")) {
    out.push(...dailySummary(input));
  }
  return out;
}
