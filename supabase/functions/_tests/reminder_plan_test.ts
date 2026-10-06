import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  couldBeDue,
  formatMoney,
  planReminders,
  type ReminderInput,
} from "../_shared/reminder_plan.ts";

const NEPAL = 345;

// 2026-10-01 is 15 Asoj 2083, a Thursday.
function input(overrides: Partial<ReminderInput> = {}): ReminderInput {
  return {
    local: { date: "2026-10-01", hour: 9 },
    utcOffsetMinutes: NEPAL,
    prefs: null,
    currency: "NPR",
    sentKeys: new Set(),
    budgets: [],
    transactions: [],
    recurring: [],
    friendCredits: [],
    pasalCredits: [],
    categoryNames: new Map([["food", "Food"]]),
    friendNames: new Map([["ram", "Ram"]]),
    pasalNames: new Map([["shop", "Hari Kirana"]]),
    ...overrides,
  };
}

const monthly = {
  id: "b1",
  category_id: null,
  period: "monthly",
  amount: 10000,
  bs_year: 2083,
  bs_month: 6,
  week_start: null,
};

function expense(amount: number, at = "2026-09-30T06:00:00Z", category = "food") {
  return { type: "expense", amount, category_id: category, occurred_at: at };
}

Deno.test("money uses Indian grouping", () => {
  assertEquals(formatMoney(1234567, "NPR"), "NPR 12,34,567");
  assertEquals(formatMoney(500, "NPR"), "NPR 500");
});

Deno.test("budget: 85% spent sends the 80% alert", () => {
  const plan = planReminders(input({
    local: { date: "2026-10-01", hour: 14 },
    budgets: [monthly],
    transactions: [expense(8500)],
  }));
  assertEquals(plan.length, 1);
  assertEquals(plan[0].category, "budget_warnings");
  assertEquals(plan[0].keys, ["budget:b1:2026-09-17:80"]);
  assert(plan[0].body.includes("85%"));
  assert(plan[0].body.includes("17 days"));
});

Deno.test("budget: over 100% sends the over-budget alert once", () => {
  const base = {
    local: { date: "2026-10-01", hour: 14 },
    budgets: [monthly],
    transactions: [expense(12000)],
  };
  const first = planReminders(input(base));
  assertEquals(first[0].title, "🚨 Over budget");
  const again = planReminders(input({ ...base, sentKeys: new Set(first[0].keys) }));
  assertEquals(again, []);
});

Deno.test("budget: spending before the BS month started does not count", () => {
  const plan = planReminders(input({
    local: { date: "2026-10-01", hour: 14 },
    budgets: [monthly],
    transactions: [expense(9000, "2026-09-10T06:00:00Z")],
  }));
  assertEquals(plan, []);
});

Deno.test("budget: quiet at night", () => {
  const plan = planReminders(input({
    local: { date: "2026-10-01", hour: 23 },
    budgets: [monthly],
    transactions: [expense(12000)],
  }));
  assertEquals(plan, []);
});

Deno.test("recurring: one bill due tomorrow", () => {
  const plan = planReminders(input({
    recurring: [{
      id: "r1",
      title: "Rent",
      amount: 15000,
      type: "expense",
      next_date: "2026-10-02",
      end_date: null,
      is_active: true,
    }],
  }));
  assertEquals(plan.length, 1);
  assertEquals(plan[0].category, "recurring_reminders");
  assertEquals(plan[0].body, "Rent: NPR 15,000 due tomorrow.");
});

Deno.test("recurring: only at the reminder hour", () => {
  const plan = planReminders(input({
    local: { date: "2026-10-01", hour: 10 },
    recurring: [{
      id: "r1",
      title: "Rent",
      amount: 15000,
      type: "expense",
      next_date: "2026-10-01",
      end_date: null,
      is_active: true,
    }],
  }));
  assertEquals(plan, []);
});

Deno.test("friend: debt due today opens the friend", () => {
  const plan = planReminders(input({
    friendCredits: [{
      id: "f1",
      friend_id: "ram",
      direction: "THEY_OWE",
      title: null,
      remaining_amount: 500,
      status: "pending",
      due_date: "2026-10-01",
    }],
  }));
  assertEquals(plan[0].category, "friend_debt_reminders");
  assertEquals(plan[0].body, "Ram owes you NPR 500, due today.");
  assertEquals(plan[0].route, "/friends/detail");
  assertEquals(plan[0].routeArgs, '"ram"');
});

Deno.test("overdue: weekly nudges, grouped when several", () => {
  const plan = planReminders(input({
    friendCredits: [{
      id: "f1",
      friend_id: "ram",
      direction: "I_OWE",
      title: null,
      remaining_amount: 300,
      status: "pending",
      due_date: "2026-09-29",
    }],
    pasalCredits: [{
      id: "p1",
      pasal_id: "shop",
      title: "Rice",
      remaining_amount: 900,
      status: "unpaid",
      due_date: "2026-09-20",
    }],
  }));
  assertEquals(plan.length, 1);
  assertEquals(plan[0].category, "overdue_reminders");
  assertEquals(plan[0].title, "⏰ 2 overdue payments");
  assertEquals(plan[0].keys, ["overdue:friend:f1:0", "overdue:pasal:p1:1"]);
  assertEquals(plan[0].route, "/");
});

Deno.test("pasal month end: second-to-last day of the BS month", () => {
  // Asoj 2083 has 31 days; day 30 is 2026-10-16.
  const plan = planReminders(input({
    local: { date: "2026-10-16", hour: 9 },
    pasalCredits: [{
      id: "p1",
      pasal_id: "shop",
      title: null,
      remaining_amount: 905,
      status: "unpaid",
      due_date: null,
    }],
  }));
  assertEquals(plan.length, 1);
  assertEquals(plan[0].category, "pasal_month_end");
  assertEquals(plan[0].title, "🏪 Asoj ends tomorrow");
  assertEquals(plan[0].keys, ["pasal-month:shop:2083-6"]);
});

Deno.test("summaries are off unless the user turned them on", () => {
  const evening = { local: { date: "2026-10-01", hour: 21 } };
  assertEquals(planReminders(input(evening)), []);
  const plan = planReminders(input({
    ...evening,
    prefs: { daily_summary: true },
    transactions: [expense(450, "2026-10-01T06:00:00Z")],
  }));
  assertEquals(plan[0].category, "daily_summary");
  assertEquals(plan[0].body, "Spent NPR 450 across 1 entry. Most went to Food.");
});

Deno.test("weekly summary goes out on Sunday morning", () => {
  // 2026-10-04 is a Sunday.
  const plan = planReminders(input({
    local: { date: "2026-10-04", hour: 9 },
    prefs: { weekly_summary: true },
    transactions: [
      expense(1000, "2026-09-30T06:00:00Z"),
      expense(500, "2026-09-24T06:00:00Z"),
    ],
  }));
  assertEquals(plan[0].category, "weekly_summary");
  assertEquals(
    plan[0].body,
    "Last week you spent NPR 1,000, 100% more than the week before. Top category: Food.",
  );
});

Deno.test("a category the user switched off never fires", () => {
  const plan = planReminders(input({
    prefs: { recurring_reminders: false },
    recurring: [{
      id: "r1",
      title: "Rent",
      amount: 15000,
      type: "expense",
      next_date: "2026-10-01",
      end_date: null,
      is_active: true,
    }],
  }));
  assertEquals(plan, []);
});

Deno.test("couldBeDue lets the worker skip idle hours", () => {
  assertEquals(couldBeDue(null, 3), false);
  assertEquals(couldBeDue(null, 9), true);
  assertEquals(couldBeDue({ budget_warnings: false }, 14), false);
});

Deno.test("monthly report: on the first of a BS month, about the one that ended", () => {
  // Kartik 2083 starts on 2026-10-18; Asoj ran from 2026-09-17.
  const first = {
    local: { date: "2026-10-18", hour: 9 },
    transactions: [
      expense(6000, "2026-09-20T06:00:00Z"),
      expense(2000, "2026-10-10T06:00:00Z"),
      {
        type: "income",
        amount: 20000,
        category_id: null,
        occurred_at: "2026-09-18T06:00:00Z",
      },
      // Bhadra, the month before it.
      expense(4000, "2026-09-01T06:00:00Z"),
      // Kartik itself is not part of the report.
      expense(999, "2026-10-18T02:00:00Z"),
    ],
  };
  const plan = planReminders(input(first));
  assertEquals(plan.length, 1);
  assertEquals(plan[0].category, "monthly_report");
  assertEquals(plan[0].title, "📅 Your Asoj report");
  assertEquals(
    plan[0].body,
    "In Asoj you spent NPR 8,000 and earned NPR 20,000, so NPR 12,000 was " +
      "saved. That is 100% more than Bhadra. Most went to Food.",
  );
  assertEquals(plan[0].keys, ["monthly:2083-6"]);
  // Opens Reports on that month.
  assertEquals(plan[0].route, "/reports");
  assertEquals(plan[0].routeArgs, '"last-month"');

  // Once, on that day, at the reminder hour, and only when there is something
  // to report and the user has not switched it off.
  const none = (overrides: Partial<ReminderInput>) =>
    assertEquals(planReminders(input({ ...first, ...overrides })), []);
  none({ local: { date: "2026-10-19", hour: 9 } });
  none({ local: { date: "2026-10-18", hour: 10 } });
  none({ sentKeys: new Set(["monthly:2083-6"]) });
  none({ transactions: [expense(999, "2026-10-18T02:00:00Z")] });
  none({ prefs: { monthly_report: false } });
});

Deno.test("monthly report: a month that cost more than it brought in says so", () => {
  const plan = planReminders(input({
    local: { date: "2026-10-18", hour: 9 },
    transactions: [
      expense(9000, "2026-09-20T06:00:00Z"),
      {
        type: "income",
        amount: 5000,
        category_id: null,
        occurred_at: "2026-09-18T06:00:00Z",
      },
    ],
  }));
  assertEquals(
    plan[0].body,
    "In Asoj you spent NPR 9,000 and earned NPR 5,000, NPR 4,000 more than " +
      "came in. Most went to Food.",
  );
});
