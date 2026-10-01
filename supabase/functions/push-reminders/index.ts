// Data-driven reminders: budget alerts, upcoming bills, friend debts, overdue
// payments, pasal month end, and the daily / weekly summaries.
//
// Invoked hourly by pg_cron (see *_push_reminders.sql) with the
// shared internal secret, like ai-daily-buddy. Each run:
//   1. finds users with a live token and works out their local time
//   2. skips users for whom nothing can be due this hour (no data loaded)
//   3. loads that user's rows and asks reminder_plan.ts what is due
//   4. claims each notification's dedupe keys in push_reminder_log, so a
//      repeated or overlapping run cannot send the same thing twice
//   5. sends through FCM; a send that reached no device releases its keys so
//      a later run retries it (budget alerts: the next hour; hour-bound
//      reminders: the next day the item is still due)
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

import { isInternalCaller, json } from "../_shared/auth.ts";
import { readServiceAccount, sendMessage } from "../_shared/fcm.ts";
import { PUSH_TYPES } from "../_shared/push_types.ts";
import { localTime } from "../_shared/buddy_schedule.ts";
import { addDays } from "../_shared/bs_calendar.ts";
import {
  couldBeDue,
  type PlannedPush,
  planReminders,
  type ReminderInput,
} from "../_shared/reminder_plan.ts";

const MAX_USERS_PER_RUN = 200;
const TRANSACTION_WINDOW_DAYS = 40;
const SENT_KEY_WINDOW_DAYS = 120;

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

interface Candidate {
  userId: string;
  prefs: Record<string, unknown> | null;
  utcOffsetMinutes: number;
  currency: string;
}

async function findCandidates(db: SupabaseClient): Promise<Candidate[]> {
  const since = new Date(Date.now() - 90 * 86_400_000).toISOString();
  const { data: tokenRows } = await db
    .from("push_tokens")
    .select("user_id")
    .gt("last_seen_at", since);
  const ids = [
    ...new Set(
      ((tokenRows ?? []) as Array<{ user_id?: string }>)
        .map((row) => row.user_id)
        .filter((id): id is string => typeof id === "string"),
    ),
  ].slice(0, MAX_USERS_PER_RUN);
  if (ids.length === 0) return [];

  const { data: settings } = await db
    .from("app_settings")
    .select("user_id,notifications,currency")
    .in("user_id", ids);
  const byUser = new Map<string, { notifications?: unknown; currency?: unknown }>();
  for (const row of (settings ?? []) as Array<Record<string, unknown>>) {
    if (typeof row.user_id === "string") byUser.set(row.user_id, row);
  }

  return ids.map((userId) => {
    const row = byUser.get(userId);
    const prefs = row?.notifications && typeof row.notifications === "object" &&
        !Array.isArray(row.notifications)
      ? row.notifications as Record<string, unknown>
      : null;
    const offset = prefs?.utc_offset_minutes;
    return {
      userId,
      prefs,
      // No reported offset means the app predates it; Nepal is the audience.
      utcOffsetMinutes: typeof offset === "number" && Number.isFinite(offset)
        ? offset
        : 345,
      currency: typeof row?.currency === "string" && row.currency.trim()
        ? row.currency.trim()
        : "NPR",
    };
  });
}

function nameMap(rows: unknown, label: string): Map<string, string> {
  const map = new Map<string, string>();
  for (const row of (rows ?? []) as Array<Record<string, unknown>>) {
    if (typeof row.id === "string" && typeof row[label] === "string") {
      map.set(row.id, row[label] as string);
    }
  }
  return map;
}

async function loadInput(
  db: SupabaseClient,
  user: Candidate,
  local: { date: string; hour: number },
): Promise<ReminderInput> {
  const id = user.userId;
  // Local midnight of the first day we need, as a UTC instant.
  const fromDay = addDays(local.date, -TRANSACTION_WINDOW_DAYS);
  const txSince = new Date(
    Date.parse(`${fromDay}T00:00:00Z`) - user.utcOffsetMinutes * 60_000,
  ).toISOString();
  const keysSince = new Date(Date.now() - SENT_KEY_WINDOW_DAYS * 86_400_000)
    .toISOString();

  const [
    budgets,
    transactions,
    recurring,
    friendCredits,
    pasalCredits,
    categories,
    friends,
    pasals,
    sent,
  ] = await Promise.all([
    db.from("budgets")
      .select("id,category_id,period,amount,bs_year,bs_month,week_start")
      .eq("user_id", id).is("deleted_at", null),
    db.from("transactions")
      .select("type,amount,category_id,occurred_at")
      .eq("user_id", id).is("deleted_at", null).eq("status", "completed")
      .gte("occurred_at", txSince),
    db.from("recurring_transactions")
      .select("id,title,amount,type,next_date,end_date,is_active")
      .eq("user_id", id).is("deleted_at", null).eq("is_active", true)
      .gte("next_date", local.date).lte("next_date", addDays(local.date, 1)),
    db.from("friend_credits")
      .select("id,friend_id,direction,title,remaining_amount,status,due_date")
      .eq("user_id", id).is("deleted_at", null).gt("remaining_amount", 0),
    db.from("pasal_credits")
      .select("id,pasal_id,title,remaining_amount,status,due_date")
      .eq("user_id", id).is("deleted_at", null).gt("remaining_amount", 0),
    db.from("categories").select("id,name").eq("user_id", id),
    db.from("friends").select("id,name").eq("user_id", id).is("deleted_at", null),
    db.from("pasals").select("id,name")
      .eq("user_id", id).is("deleted_at", null).eq("is_active", true),
    db.from("push_reminder_log").select("key")
      .eq("user_id", id).gte("created_at", keysSince),
  ]);

  return {
    local,
    utcOffsetMinutes: user.utcOffsetMinutes,
    prefs: user.prefs,
    currency: user.currency,
    sentKeys: new Set(
      ((sent.data ?? []) as Array<{ key: string }>).map((row) => row.key),
    ),
    budgets: (budgets.data ?? []) as ReminderInput["budgets"],
    transactions: (transactions.data ?? []) as ReminderInput["transactions"],
    recurring: (recurring.data ?? []) as ReminderInput["recurring"],
    friendCredits: (friendCredits.data ?? []) as ReminderInput["friendCredits"],
    pasalCredits: (pasalCredits.data ?? []) as ReminderInput["pasalCredits"],
    categoryNames: nameMap(categories.data, "name"),
    friendNames: nameMap(friends.data, "name"),
    pasalNames: nameMap(pasals.data, "name"),
  };
}

/** Claims every key of a push; false when another run already holds one. */
async function claim(
  db: SupabaseClient,
  userId: string,
  push: PlannedPush,
): Promise<boolean> {
  const { data, error } = await db
    .from("push_reminder_log")
    .upsert(
      push.keys.map((key) => ({ user_id: userId, key, category: push.category })),
      { onConflict: "user_id,key", ignoreDuplicates: true },
    )
    .select("key");
  if (error) return false;
  return (data ?? []).length === push.keys.length;
}

async function release(db: SupabaseClient, userId: string, keys: string[]) {
  await db.from("push_reminder_log").delete().eq("user_id", userId).in(
    "key",
    keys,
  );
}

async function deliver(
  db: SupabaseClient,
  userId: string,
  push: PlannedPush,
): Promise<number> {
  const { data: tokenRows } = await db
    .from("push_tokens")
    .select("token")
    .eq("user_id", userId);
  const spec = PUSH_TYPES[push.category];
  const data: Record<string, string> = {
    category: push.category,
    title: push.title,
    body: push.body,
    route: push.route,
  };
  if (push.routeArgs) data.route_args = push.routeArgs;

  const dead: string[] = [];
  let sent = 0;
  for (const { token } of (tokenRows ?? []) as Array<{ token: string }>) {
    const result = await sendMessage({
      token,
      data,
      android: {
        // Every reminder ends in a visible notification, so high priority is
        // legitimate and keeps Doze from holding it past the moment it matters.
        priority: "high",
        ttl: spec?.ttl ?? "86400s",
      },
    });
    if (result.ok) sent += 1;
    else if (result.unregistered) dead.push(result.token);
  }
  if (dead.length > 0) {
    await db.from("push_tokens").delete().in("token", dead);
  }
  return sent;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!(await isInternalCaller(req, supabase))) {
    return json({ error: "Not authorized" }, 401);
  }
  if (!readServiceAccount()) {
    return json({ error: "FIREBASE_SERVICE_ACCOUNT_JSON is not configured" }, 500);
  }

  const now = new Date();
  const users = await findCandidates(supabase);
  let checked = 0;
  let sent = 0;
  let failed = 0;
  const byCategory: Record<string, number> = {};

  for (const user of users) {
    const local = localTime(now, user.utcOffsetMinutes);
    if (!couldBeDue(user.prefs, local.hour)) continue;
    checked += 1;
    try {
      const input = await loadInput(supabase, user, local);
      for (const push of planReminders(input)) {
        if (!(await claim(supabase, user.userId, push))) continue;
        const delivered = await deliver(supabase, user.userId, push);
        if (delivered > 0) {
          sent += 1;
          byCategory[push.category] = (byCategory[push.category] ?? 0) + 1;
        } else {
          failed += 1;
          await release(supabase, user.userId, push.keys);
        }
      }
    } catch (error) {
      console.error("push-reminders: user failed", user.userId, error);
      failed += 1;
    }
  }

  return json({ ok: true, candidates: users.length, checked, sent, failed, byCategory });
});
