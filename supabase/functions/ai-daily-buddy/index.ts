// The flame's daily chatter, delivered as push notifications.
//
// Invoked every 15 minutes by pg_cron (see *_schedule_ai_daily_buddy.sql) with
// the shared internal secret, exactly like ai-push-digest. Each run:
//   1. finds users who have not turned `daily_buddy` off and have a live token
//   2. works out each user's local time from their reported UTC offset
//   3. keeps only users with a slot due right now (06:00, 22:00, or one of
//      their random daytime quarter-hours) that has not already been sent
//   4. writes a short line with the model (canned fallback if it fails)
//   5. sends through FCM and logs the result
//
// Step 3 happens before any model call, so the ~95 runs a day where nothing is
// due for anyone cost two small queries and no tokens.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

import { isInternalCaller, json } from "../_shared/auth.ts";
import { readServiceAccount, sendMessage } from "../_shared/fcm.ts";
import { buildFinancialSummary } from "../_shared/summary.ts";
import { generateBuddyMessage } from "../_shared/ai.ts";
import {
  BUDDY_PROMPT_VERSION,
  BUDDY_SYSTEM_PROMPT,
  buildBuddyUserPrompt,
} from "../_shared/prompt.ts";
import {
  DAY_ANGLES,
  dayPart,
  dueSlot,
  localTime,
  slotSeed,
} from "../_shared/buddy_schedule.ts";

const CATEGORY = "daily_buddy";
const MAX_USERS_PER_RUN = 200;
const WEEKDAYS = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
];

interface Candidate {
  userId: string;
  utcOffsetMinutes: number | null;
  name: string | null;
}

async function findCandidates(supabase: SupabaseClient): Promise<Candidate[]> {
  const [settings, tokens] = await Promise.all([
    supabase.from("app_settings").select("user_id,notifications,profile"),
    supabase
      .from("push_tokens")
      .select("user_id")
      .gt(
        "last_seen_at",
        new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString(),
      ),
  ]);

  const withToken = new Set<string>();
  for (const row of (tokens.data ?? []) as Array<{ user_id?: string }>) {
    if (typeof row.user_id === "string") withToken.add(row.user_id);
  }

  const result: Candidate[] = [];
  for (
    const row of (settings.data ?? []) as Array<{
      user_id?: string;
      notifications?: Record<string, unknown> | null;
      profile?: { full_name?: unknown } | null;
    }>
  ) {
    const id = row.user_id;
    if (typeof id !== "string" || !withToken.has(id)) continue;
    // On by default: only an explicit `false` opts out.
    if (row.notifications?.daily_buddy === false) continue;
    const raw = row.notifications?.utc_offset_minutes;
    const name = row.profile?.full_name;
    result.push({
      userId: id,
      utcOffsetMinutes: typeof raw === "number" && Number.isFinite(raw)
        ? raw
        : null,
      name: typeof name === "string" && name.trim() ? name.trim() : null,
    });
    if (result.length >= MAX_USERS_PER_RUN) break;
  }
  return result;
}

async function alreadySent(
  supabase: SupabaseClient,
  userId: string,
  key: string,
): Promise<boolean> {
  const { data } = await supabase
    .from("ai_notification_log")
    .select("id")
    .eq("user_id", userId)
    .eq("fingerprint", key)
    .eq("status", "sent")
    .limit(1);
  return (data ?? []).length > 0;
}

/**
 * What the flame told this user lately, newest first. Passed to the model and
 * to the canned fallback so neither says the same thing again.
 */
async function recentLines(
  supabase: SupabaseClient,
  userId: string,
): Promise<string[]> {
  const { data } = await supabase
    .from("ai_notification_log")
    .select("body")
    .eq("user_id", userId)
    .eq("category", CATEGORY)
    .eq("status", "sent")
    .order("created_at", { ascending: false })
    .limit(8);
  return ((data ?? []) as Array<{ body?: string | null }>)
    .map((row) => row.body)
    .filter((body): body is string => typeof body === "string" && body !== "");
}

async function sendToUser(
  supabase: SupabaseClient,
  userId: string,
  message: { title: string; body: string },
): Promise<{ sent: number; pruned: number }> {
  const { data: tokenRows } = await supabase
    .from("push_tokens")
    .select("token")
    .eq("user_id", userId);
  const tokens = ((tokenRows ?? []) as Array<{ token: string }>).map((r) =>
    r.token
  );
  const dead: string[] = [];
  let sent = 0;
  for (const token of tokens) {
    const result = await sendMessage({
      token,
      data: {
        category: CATEGORY,
        title: message.title,
        body: message.body,
        route: "/",
      },
      android: {
        // High so Doze does not hold the 06:00 greeting until the phone's
        // next maintenance window; every buddy push ends in a visible
        // notification, which is what FCM expects of high priority.
        priority: "high",
        ttl: "1800s",
        collapseKey: "daily-buddy",
      },
    });
    if (result.ok) sent += 1;
    else if (result.unregistered) dead.push(result.token);
  }
  if (dead.length > 0) {
    await supabase.from("push_tokens").delete().in("token", dead);
  }
  return { sent, pruned: dead.length };
}

Deno.serve(async (req) => {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return json({ error: "Server is not configured" }, 500);

  // Service role: every query below is scoped by an explicit user_id.
  const supabase = createClient(url, serviceKey, {
    auth: { persistSession: false },
  });
  if (!(await isInternalCaller(req, supabase))) {
    return json({ error: "Unauthorized" }, 401);
  }

  const { data: config } = await supabase
    .from("ai_push_config")
    .select("buddy_enabled, buddy_daytime_per_day")
    .limit(1)
    .maybeSingle();
  const row = config as
    | { buddy_enabled?: boolean; buddy_daytime_per_day?: number }
    | null;
  if (row?.buddy_enabled === false) {
    return json({ ok: true, skipped: "disabled" });
  }
  const perDay = Math.max(0, Math.min(6, row?.buddy_daytime_per_day ?? 2));

  if (!readServiceAccount()) {
    return json({ error: "FIREBASE_SERVICE_ACCOUNT_JSON is not configured" }, 500);
  }

  const now = new Date();
  const stats = { candidates: 0, due: 0, sent: 0, failed: 0, fallback: 0 };
  const candidates = await findCandidates(supabase);
  stats.candidates = candidates.length;

  for (const user of candidates) {
    try {
      const local = localTime(now, user.utcOffsetMinutes);
      const due = dueSlot(user.userId, local, perDay);
      if (!due) continue;
      if (await alreadySent(supabase, user.userId, due.key)) continue;
      stats.due += 1;

      const summary = await buildFinancialSummary(supabase, {
        windowDays: 30,
        userId: user.userId,
      });
      // The summary buckets by UTC day and lists only days with spending.
      const todayKey = now.toISOString().slice(0, 10);
      const today =
        summary.dailyExpense.find((d) => d.date === todayKey)?.amount ?? 0;
      const weekday = WEEKDAYS[
        new Date(`${local.date}T00:00:00Z`).getUTCDay()
      ];

      const seed = slotSeed(user.userId, due.key);
      const part = due.slot === "day" ? dayPart(local.hour) : null;
      const recent = await recentLines(supabase, user.userId);
      const clock = `${String(local.hour).padStart(2, "0")}:${
        String(local.minute).padStart(2, "0")
      }`;

      const message = await generateBuddyMessage(
        BUDDY_SYSTEM_PROMPT,
        buildBuddyUserPrompt({
          slot: due.slot,
          timeOfDay: part ?? due.slot,
          localTime: clock,
          angle: DAY_ANGLES[seed % DAY_ANGLES.length],
          recent,
          name: user.name,
          currency: summary.currency,
          incomeThisMonth: summary.totals.incomeThisWindow,
          expenseThisMonth: summary.totals.expenseThisWindow,
          expenseToday: today,
          topCategory: summary.categories[0]?.name ?? null,
          weekday,
        }),
        due.slot,
        seed,
        { part, recent },
      );
      if (message.source === "fallback") stats.fallback += 1;

      const { sent, pruned } = await sendToUser(supabase, user.userId, {
        title: message.title,
        body: message.message,
      });

      await supabase.from("ai_notification_log").insert({
        user_id: user.userId,
        status: sent > 0 ? "sent" : "failed",
        category: CATEGORY,
        topic: due.slot,
        priority: "low",
        deep_link: "/",
        fingerprint: due.key,
        title: message.title,
        body: message.message,
        prompt_version: `${BUDDY_PROMPT_VERSION}:${message.source}`,
        window_days: 30,
        tokens_sent: sent,
        tokens_pruned: pruned,
      });
      if (sent > 0) stats.sent += 1;
      else stats.failed += 1;
    } catch (error) {
      stats.failed += 1;
      console.error("buddy: user failed", user.userId, String(error));
    }
  }

  return json({ ok: true, ...stats });
});
