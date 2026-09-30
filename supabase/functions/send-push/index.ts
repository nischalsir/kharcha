// Sends a push notification to one user, one token, or a topic.
//
// This is the single reusable entry point for every push in Kharcha. Features
// (a budget crossing a limit, a friend adding a debt, a nightly digest) call
// it rather than talking to FCM directly, so preferences, invalid-token
// cleanup and audit logging all happen in exactly one place.
//
// Authentication, in order of precedence:
//   1. A user JWT. The caller may only notify *themselves*, which is what lets
//      the app trigger its own reminders without a server round trip.
//   2. `x-kharcha-internal-secret` matching the secret in `ai_push_worker`, for
//
// `verify_jwt` is off at the function level precisely so path 2 can work: a
// pg_cron invocation has no user JWT to present, and the platform's own check
// would reject it before this function could look at anything.
import { createClient } from "npm:@supabase/supabase-js@2";

import {
  badRequest,
  corsHeaders,
  getUser,
  isInternalCaller,
  json,
  serverError,
  unauthorized,
} from "../_shared/auth.ts";
import {
  readServiceAccount,
  sendMessage,
  type SendResult,
} from "../_shared/fcm.ts";
import { PUSH_TYPES, resolveChannel } from "../_shared/push_types.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

const MAX_BODY_LEN = 20_000;
// Guards against one request fanning out to an unbounded number of devices.
const MAX_TOKENS_PER_SEND = 100;
const SEND_CONCURRENCY = 10;

type SendTarget = "self" | "user" | "tokens" | "topic";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // Authorize before touching configuration. The order matters: checking the
  // service account first would let anyone who cannot authenticate tell a
  // misconfigured server apart from a rejected request, and would make every
  // anonymous hit pay for a service-account parse.
  const caller = await getUser(req);
  const internal = !caller && (await isInternalCaller(req, supabase));
  if (!caller && !internal) return unauthorized();

  if (!readServiceAccount()) {
    return serverError("Push is not configured on this server.");
  }

  const raw = await req.text();
  if (raw.length > MAX_BODY_LEN) return badRequest("Request body is too large");

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return badRequest("Invalid JSON body");
  }

  const category = String(body.category ?? "");
  const spec = PUSH_TYPES[category];
  if (!spec) {
    return badRequest(
      `Unknown category '${category}'. Known: ${
        Object.keys(PUSH_TYPES).join(", ")
      }`,
    );
  }

  const title = String(body.title ?? spec.title ?? "").slice(0, 120).trim();
  const bodyText = String(body.body ?? "").slice(0, 400).trim();
  if (!title || !bodyText) {
    return badRequest("Both title and body are required");
  }

  const target = String(
    body.target ?? (caller ? "self" : "user"),
  ) as SendTarget;
  const data = sanitizeData(body.data);
  const channelId = resolveChannel(category);

  // ---------------------------------------------------------------- targeting
  const tokens: string[] = [];
  let topic: string | undefined;
  let recipients = 0;
  let prefs: Record<string, boolean> | null = null;

  if (target === "topic") {
    const normalized = normalizeTopic(body.topic);
    if (!normalized) return badRequest("Invalid topic name");
    topic = normalized;
  } else if (target === "tokens") {
    if (!internal) {
      return unauthorized("Only the server can send to raw tokens");
    }
    const list = Array.isArray(body.tokens) ? body.tokens : [];
    for (const item of list.slice(0, MAX_TOKENS_PER_SEND)) {
      if (typeof item === "string" && item.trim()) tokens.push(item.trim());
    }
    if (tokens.length === 0) return badRequest("No valid tokens supplied");
  } else {
    let userId: string | null = null;
    if (target === "self") {
      userId = caller!.id;
    } else {
      if (!internal) {
        return unauthorized("Only the server can notify another user");
      }
      userId = typeof body.user_id === "string" ? body.user_id : null;
      if (!userId) return badRequest("user_id is required");
    }

    const result = await loadTargetTokens(userId);
    if ("error" in result) return serverError(result.error);
    tokens.push(...result.tokens);
    prefs = result.prefs;

    // Honour the recipient's opt-out. `prefs === null` means the user has no
    // app_settings row, which happens on a brand-new account; fall back to the
    // category default rather than sending nothing.
    if (prefs && prefs[spec.prefKey] === false) {
      return json({
        sent: 0,
        skipped: "preference_disabled",
        category,
        preferenceKey: spec.prefKey,
      });
    }
  }

  if (!topic && tokens.length === 0) {
    return json({ sent: 0, skipped: "no_tokens", category });
  }
  recipients = topic ? 1 : tokens.length;

  // ------------------------------------------------------------------- send
  const payload = {
    ...data,
    title,
    body: bodyText,
    category,
  };

  if (topic) {
    const result = await sendMessage({
      topic,
      data: payload,
      android: {
        priority: spec.priority,
        ttl: spec.ttl,
        notification: { channelId },
      },
    });
    return json({
      sent: result.ok ? 1 : 0,
      failed: result.ok ? 0 : 1,
      topic,
      category,
      detail: result.ok
        ? undefined
        : { code: result.code, status: result.status },
    });
  }

  const results = await sendInBatches(tokens, (token) =>
    sendMessage({
      token,
      data: payload,
      android: {
        priority: spec.priority,
        ttl: spec.ttl,
        notification: { channelId },
      },
    }));

  // Delete tokens FCM has told us are permanently dead. Leaving them would mean
  // every future notification to this user pays for a guaranteed failure, and
  // the count would drift upward forever.
  // Narrowed to the failure arm: a successful SendResult carries no `token`.
  const dead = results
    .filter((r): r is Extract<SendResult, { ok: false }> =>
      !r.ok && r.unregistered
    )
    .map((r) => r.token);
  if (dead.length > 0) {
    await supabase.from("push_tokens").delete().in("token", dead);
  }

  const sent = results.filter((r) => r.ok).length;
  const failed = results.length - sent;

  return json({
    sent,
    failed,
    removedTokens: dead.length,
    category,
    channelId,
    recipients,
    // Surface the first failure's code so a misconfigured server (wrong project,
    // wrong VAPID, bad service account) is diagnosable from the app's logs
    // instead of looking like "no notifications arriving".
    detail: failed > 0
      ? { firstError: results.find((r) => !r.ok)?.code }
      : undefined,
  });
});

/**
 * Loads a user's live tokens and their notification preferences.
 *
 * Preferences are read from `app_settings.notifications`, the same jsonb column
 * the settings screen writes, so there is exactly one source of truth for what
 * a user has opted into.
 */
async function loadTargetTokens(
  userId: string,
): Promise<
  { tokens: string[]; prefs: Record<string, boolean> | null } | {
    error: string;
  }
> {
  const [{ data: tokenRows, error: tokenError }, { data: settings }] =
    await Promise.all([
      supabase.from("push_tokens").select("token").eq("user_id", userId),
      supabase
        .from("app_settings")
        .select("notifications")
        .eq("user_id", userId)
        .maybeSingle(),
    ]);

  if (tokenError) return { error: "Could not read push tokens" };

  const tokens = (tokenRows ?? [])
    .map((row) => (typeof row.token === "string" ? row.token.trim() : ""))
    .filter((value) => value.length > 0);

  const raw = settings?.notifications;
  const prefs = raw && typeof raw === "object" && !Array.isArray(raw)
    ? (raw as Record<string, boolean>)
    : null;

  return { tokens, prefs };
}

/** Runs `worker` over `items` with a bounded number of in-flight requests. */
async function sendInBatches<T, R>(
  items: T[],
  worker: (item: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let cursor = 0;
  const runnerCount = Math.min(SEND_CONCURRENCY, items.length);
  await Promise.all(
    Array.from({ length: runnerCount }, async () => {
      while (cursor < items.length) {
        const index = cursor++;
        results[index] = await worker(items[index]);
      }
    }),
  );
  return results;
}

/**
 * Coerces `data` to string-only, which FCM requires.
 *
 * Nested objects are dropped rather than stringified: a notification that
 * stringifies an object into a payload is usually a bug at the call site, and a
 * 400 from FCM is a worse failure mode than a missing optional key.
 */
function sanitizeData(raw: unknown): Record<string, string> {
  const out: Record<string, string> = {};
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out;
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    if (value == null) continue;
    if (typeof value === "object") continue;
    if (key.length > 64) continue;
    out[key.slice(0, 64)] = String(value).slice(0, 500);
  }
  return out;
}

/** FCM topic names are `[a-zA-Z0-9-_.~%]+`. */
function normalizeTopic(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const topic = raw.trim().replace(/^\/topics\//, "");
  if (!/^[a-zA-Z0-9-_.~%]+$/.test(topic)) return null;
  if (topic.length > 900) return null;
  return topic;
}
