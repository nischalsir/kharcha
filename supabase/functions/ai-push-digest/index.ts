// Scheduled AI push worker.
//
// Invoked by pg_cron through pg_net (see supabase/migrations/*_ai_push_log_and_config.sql)
// with the `x-kharcha-internal-secret` header, never with a user JWT: there is
// no user to authenticate at 06:17, and one user must not be able to trigger a
// model call for every other user.
//
// The pipeline, and why each stage exists:
//   1. load config            - schedule/cooldowns are data, not code
//   2. find eligible users    - opted in to `ai_content`, has a live token
//   3. build summary          - the SAME aggregator the Home widget uses
//   4. cheap pre-filter       - no data / recently notified / in cooldown:
//                               skipped BEFORE spending a token on the model
//   5. generate               - one model call, with the user's own history
//   6. decide                 - deterministic gate; the model does not get to
//                               decide on its own whether to interrupt someone
//   7. send + record          - reuse the existing FCM transport, log the outcome
//
// Step 4 is the reason this runs as a job and not per-request: most users will
// be filtered out without a model call, and the model is the only expensive part.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

import { isInternalCaller, json } from "../_shared/auth.ts";
import { readServiceAccount, sendMessage } from "../_shared/fcm.ts";
import { buildFinancialSummary } from "../_shared/summary.ts";
import {
  AI_PUSH_CATEGORY,
  generatePushInsight,
  PushNotWorthSending,
} from "../_shared/ai.ts";
import {
  buildPushUserPrompt,
  PUSH_DEEP_LINKS,
  PUSH_PROMPT_VERSION,
  PUSH_SYSTEM_PROMPT,
} from "../_shared/prompt.ts";
import {
  decide,
  type DecisionConfig,
  DEFAULT_DECISION_CONFIG,
  fingerprintInsight,
} from "../_shared/notification_decision.ts";
import { resolveChannel } from "../_shared/push_types.ts";

const MAX_USERS_PER_RUN = 200;

interface PushConfigRow {
  schedule: string;
  enabled: boolean;
  window_days: number;
  min_priority: "low" | "normal" | "high";
  min_hours_between_pushes: number;
  min_hours_per_category: number;
  dedupe_window: number;
  respect_quiet_hours: boolean;
}

type LogRow = {
  user_id: string;
  status: "sent" | "skipped" | "failed";
  created_at: string;
  /** Delivery category. Rows written before the split hold a topic here. */
  category: string | null;
  topic: string | null;
  fingerprint: string | null;
};

function toDecisionConfig(row: PushConfigRow): DecisionConfig {
  return {
    ...DEFAULT_DECISION_CONFIG,
    minPriority: row.min_priority,
    minHoursBetweenPushes: row.min_hours_between_pushes,
    minHoursPerTopic: row.min_hours_per_category,
    dedupeWindow: row.dedupe_window,
    respectQuietHours: row.respect_quiet_hours,
  };
}

/**
 * Users who could receive a push: opted in to `ai_content`, and holding at least
 * one token that has been seen recently.
 *
 * The token recency filter matters because a token row outlives the app on the
 * device: without it, every user who once installed Kharcha is billed for a
 * model call on a device that is no longer there.
 */
async function findEligibleUsers(
  supabase: SupabaseClient,
): Promise<Array<{ userId: string; utcOffsetMinutes: number | null }>> {
  const [settings, tokens] = await Promise.all([
    supabase
      .from("app_settings")
      .select("user_id,notifications")
      .eq("notifications->>ai_content", "true"),
    supabase
      .from("push_tokens")
      .select("user_id")
      .gt(
        "last_seen_at",
        new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString(),
      ),
  ]);

  // Carries the device offset so quiet hours can be evaluated where the user
  // is, not in UTC. A user who has never reported one is left null, which the
  // decision engine treats as UTC rather than as "no quiet hours".
  const optedIn = new Map<string, number | null>();
  for (
    const row of (settings.data ?? []) as Array<{
      user_id?: string;
      notifications?: { utc_offset_minutes?: unknown } | null;
    }>
  ) {
    if (typeof row.user_id !== "string") continue;
    const raw = row.notifications?.utc_offset_minutes;
    optedIn.set(
      row.user_id,
      typeof raw === "number" && Number.isFinite(raw) ? raw : null,
    );
  }

  const seen = new Set<string>();
  const eligible: Array<{ userId: string; utcOffsetMinutes: number | null }> =
    [];
  for (const row of (tokens.data ?? []) as Array<{ user_id?: string }>) {
    const id = row.user_id;
    if (typeof id !== "string" || seen.has(id) || !optedIn.has(id)) continue;
    seen.add(id);
    eligible.push({ userId: id, utcOffsetMinutes: optedIn.get(id) ?? null });
    if (eligible.length >= MAX_USERS_PER_RUN) break;
  }
  return eligible;
}

interface SendHistory {
  lastNotifiedAt: string | null;
  /** Topic of the most recent push, for telling the model what came before. */
  lastTopic: string | null;
  /** Newest delivery time per topic, so the cooldown can match on topic. */
  lastSentAtByTopic: Record<string, string>;
  recentFingerprints: string[];
}

async function loadHistory(
  supabase: SupabaseClient,
  userId: string,
): Promise<SendHistory> {
  const { data } = await supabase
    .from("ai_notification_log")
    .select("topic, fingerprint, created_at")
    .eq("user_id", userId)
    .eq("status", "sent")
    // Daily-buddy greetings share this log but are not insights: counting them
    // would let a 06:00 "good morning" hold the insight cooldown all day.
    .or("category.is.null,category.neq.daily_buddy")
    .order("created_at", { ascending: false })
    .limit(25);

  const rows = (data ?? []) as LogRow[];
  const lastSentAtByTopic: Record<string, string> = {};
  for (const row of rows) {
    // Rows written before the topic column existed have a category but no
    // topic. Falling back to it keeps their cooldown rather than treating those
    // users as never having been told anything.
    const topic = row.topic ?? row.category;
    if (topic && !lastSentAtByTopic[topic]) {
      lastSentAtByTopic[topic] = row.created_at;
    }
  }

  return {
    lastNotifiedAt: rows[0]?.created_at ?? null,
    lastTopic: rows.map((row) => row.topic ?? row.category).find((t) => !!t) ??
      null,
    lastSentAtByTopic,
    recentFingerprints: rows
      .map((row) => row.fingerprint)
      .filter((value): value is string => typeof value === "string"),
  };
}

async function record(
  supabase: SupabaseClient,
  entry: Record<string, unknown>,
): Promise<void> {
  // Best effort: losing an audit row is far less bad than failing the run after
  // a push has already gone out.
  const { error } = await supabase.from("ai_notification_log").insert(entry);
  if (error) console.error("ai-push: could not record decision", error.message);
}

async function sendToUser(
  supabase: SupabaseClient,
  userId: string,
  message: { title: string; body: string; route: string },
  priority: "low" | "normal" | "high",
): Promise<{ sent: number; pruned: number }> {
  const { data: tokenRows } = await supabase
    .from("push_tokens")
    .select("id, token")
    .eq("user_id", userId);

  const tokens = ((tokenRows ?? []) as Array<{ id: string; token: string }>)
    .map(
      (row) => row.token,
    );
  if (tokens.length === 0) return { sent: 0, pruned: 0 };

  const channel = resolveChannel(AI_PUSH_CATEGORY);
  const dead: string[] = [];
  let sent = 0;

  // Sequential on purpose: a burst of parallel sends from one isolate trips
  // FCM's per-project quota, and a single user rarely has more than a handful
  // of devices.
  for (const token of tokens) {
    const result = await sendMessage({
      token,
      data: {
        category: AI_PUSH_CATEGORY,
        title: message.title,
        body: message.body,
        route: message.route,
      },
      android: {
        priority: priority === "high" ? "high" : "normal",
        ttl: "3600s",
        // One notification per insight on the device: a re-send of the same
        // push replaces rather than stacks.
        collapseKey: `ai-${message.route}`.slice(0, 32),
        notification: { channelId: channel },
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
  if (!url || !serviceKey) {
    return json({ error: "Server is not configured" }, 500);
  }
  // Service role, but every read below passes an explicit user_id. RLS does not
  // apply to this client, so the scoping is ours to get right.
  const supabase = createClient(url, serviceKey, {
    auth: { persistSession: false },
  });

  // After the client exists, because authenticating the caller now needs a
  // lookup. Built before the service-account check on purpose: refusing an
  // unauthenticated caller first is what keeps this endpoint from being a probe
  // for the function's configuration.
  if (!(await isInternalCaller(req, supabase))) {
    return json({ error: "Unauthorized" }, 401);
  }

  const { data: configRow, error: configError } = await supabase
    .from("ai_push_config")
    .select("*")
    .limit(1)
    .maybeSingle();
  if (configError) {
    return json({ error: configError.message }, 500);
  }
  const config = configRow as PushConfigRow | null;
  if (!config) {
    return json({ error: "ai_push_config has no row" }, 500);
  }
  // Checked before the service account, so a switched-off worker is a clean
  // no-op that logs nothing worth reading. A missing FCM secret should surface
  // at the moment somebody turns the feature on, not as nightly noise from a
  // feature that is deliberately off.
  if (!config.enabled) {
    return json({ ok: true, skipped: "disabled", users: 0 });
  }

  if (!readServiceAccount()) {
    return json(
      { error: "FIREBASE_SERVICE_ACCOUNT_JSON is not configured" },
      500,
    );
  }

  const decisionConfig = toDecisionConfig(config);
  const users = await findEligibleUsers(supabase);
  const summary = { eligible: users.length, sent: 0, skipped: 0, failed: 0 };

  for (const { userId, utcOffsetMinutes } of users) {
    // One bad user must not abort the whole batch, which is why this loop
    // catches rather than propagates.
    try {
      const history = await loadHistory(supabase, userId);
      const financial = await buildFinancialSummary(supabase, {
        windowDays: config.window_days,
        userId,
      });

      // Cheapest possible pre-check, before any model call.
      if (!financial.hasEnoughData) {
        summary.skipped += 1;
        await record(supabase, {
          user_id: userId,
          status: "skipped",
          skip_reason: "insufficient_data",
          prompt_version: PUSH_PROMPT_VERSION,
          window_days: config.window_days,
        });
        continue;
      }

      const base = {
        userId,
        fingerprint: "",
        lastNotifiedAt: history.lastNotifiedAt,
        recentFingerprints: history.recentFingerprints,
        hasEnoughData: financial.hasEnoughData,
        utcOffsetMinutes,
      };

      // A cooldown hit here is the common case, and the reason the model call
      // is guarded rather than unconditional. The synthetic insight uses the
      // configured minimum priority so a `minPriority: 'high'` setup is not
      // rejected at the gate before the model ever gets a say.
      //
      // The per-topic rule is deliberately left off this pre-check: the topic
      // only exists once the model has chosen one, so applying it here would
      // either block everyone or block no one.
      const preflight = decide(
        {
          ...base,
          insight: preflightInsight(decisionConfig.minPriority),
          lastTopicNotified: null,
        },
        decisionConfig,
      );
      if (!preflight.send) {
        summary.skipped += 1;
        await record(supabase, {
          user_id: userId,
          status: "skipped",
          skip_reason: preflight.reason,
          prompt_version: PUSH_PROMPT_VERSION,
          window_days: config.window_days,
        });
        continue;
      }

      const insight = await generatePushInsight(
        PUSH_SYSTEM_PROMPT,
        buildPushUserPrompt(financial, { windowDays: config.window_days }, {
          lastNotifiedAt: history.lastNotifiedAt,
          lastTopic: history.lastTopic,
        }),
        PUSH_PROMPT_VERSION,
        PUSH_DEEP_LINKS,
      );

      const fingerprint = fingerprintInsight(insight);
      const lastSentInTopic = history.lastSentAtByTopic[insight.topic];
      const verdict = decide(
        {
          ...base,
          insight,
          fingerprint,
          lastTopicNotified: lastSentInTopic
            ? { topic: insight.topic, at: lastSentInTopic }
            : null,
        },
        decisionConfig,
      );

      if (!verdict.send) {
        summary.skipped += 1;
        await record(supabase, {
          user_id: userId,
          status: "skipped",
          skip_reason: verdict.reason,
          category: AI_PUSH_CATEGORY,
          topic: insight.topic,
          priority: insight.priority,
          deep_link: insight.deepLink,
          fingerprint,
          title: insight.title,
          body: insight.message,
          prompt_version: PUSH_PROMPT_VERSION,
          window_days: config.window_days,
        });
        continue;
      }

      const { sent, pruned } = await sendToUser(
        supabase,
        userId,
        {
          title: insight.title,
          body: insight.message,
          route: insight.deepLink,
        },
        insight.priority,
      );

      await record(supabase, {
        user_id: userId,
        // A model-approved push that reached nobody is a failure, not a skip:
        // it must not satisfy the cooldown, or the next run would stay silent
        // for a user whose device is simply unregistered.
        status: sent > 0 ? "sent" : "failed",
        category: AI_PUSH_CATEGORY,
        topic: insight.topic,
        priority: insight.priority,
        deep_link: insight.deepLink,
        fingerprint,
        title: insight.title,
        body: insight.message,
        prompt_version: PUSH_PROMPT_VERSION,
        window_days: config.window_days,
        tokens_sent: sent,
        tokens_pruned: pruned,
      });
      if (sent > 0) summary.sent += 1;
      else summary.failed += 1;
    } catch (error) {
      if (error instanceof PushNotWorthSending) {
        summary.skipped += 1;
        await record(supabase, {
          user_id: userId,
          status: "skipped",
          skip_reason: "model_declined",
          prompt_version: PUSH_PROMPT_VERSION,
          window_days: config.window_days,
        });
        continue;
      }
      summary.failed += 1;
      console.error("ai-push: user failed", userId, String(error));
      await record(supabase, {
        user_id: userId,
        status: "failed",
        prompt_version: PUSH_PROMPT_VERSION,
        window_days: config.window_days,
      });
    }
  }

  return json({ ok: true, ...summary });
});

/**
 * A synthetic insight used to evaluate the cooldown rules before spending a
 * model call. It never reaches the sender: only the decision is read, and the
 * real insight replaces it afterwards.
 *
 * [priority] must be the configured minimum, otherwise a strict
 * `minPriority: 'high'` policy would be rejected at the preflight and the model
 * would never be asked at all.
 */
function preflightInsight(priority: "low" | "normal" | "high") {
  return {
    shouldNotify: true,
    title: "preflight",
    message: "preflight",
    topic: "general" as const,
    priority,
    deepLink: "/",
    promptVersion: PUSH_PROMPT_VERSION,
  };
}
