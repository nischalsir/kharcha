// Admin-facing push console backend.
//
// `send-push` is the internal primitive: it can target one user, raw tokens or a
// topic, but it cannot fan out to every account at once and it reports no
// history. This function is what the Kharcha Push Console app talks to. It adds
// the three things the console needs and nothing else:
//
//   1. Broadcast to every user with at least one live token, in bounded chunks.
//   2. A user directory (display name, email, device count, preferences) so the
//      app can render a picker instead of asking someone to type a UUID.
//   3. An append-only log of every send, so a misfire is diagnosable after the
//      fact rather than being a "did it work?" guess.
//
// Authorization is a bearer JWT whose email is in ADMIN_EMAILS. There is no
// password: the console is a single-operator tool, so the identity provider
// (Supabase Auth) is the gate and the app has no credential of its own to leak.
// The Firebase service account and the send-push internal secret are read from
// function secrets here, never shipped to the client.
//
// `verify_jwt` is off at the function level because the check below needs the
// decoded email, and because `send-push` is called with the internal secret
// rather than the caller's JWT. It is safe to leave off: every path through this
// function re-validates the caller before any secret is read or any message is
// sent.
// Authorization is a bearer JWT whose email is in ADMIN_EMAILS. There is no
// password: the console is a single-operator tool, so the identity provider
// (Supabase Auth) is the gate and the app has no credential of its own to leak.
//
// `verify_jwt` is off at the function level because the check below needs the
// decoded email, and because `send-push` is called with the internal secret
// rather than the caller's JWT. It is safe to leave off: every path through this
// function re-validates the caller before any secret is read or any message is
// sent -- and the one path that cannot present a JWT, the cron dispatcher, has
// to present the internal secret instead, which is checked just as strictly.
import { createClient } from "npm:@supabase/supabase-js@2";

import {
  badRequest,
  corsHeaders,
  isInternalCaller,
  json,
  serverError,
  unauthorized,
} from "../_shared/auth.ts";
import { pictureUrl, readServiceAccount, sendMessage } from "../_shared/fcm.ts";
import { PUSH_TYPES, resolveChannel } from "../_shared/push_types.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

const MAX_BODY_LEN = 20_000;
// Broadcast is chunked so one oversized user base cannot open thousands of
// concurrent FCM sockets in a single isolate.
const BROADCAST_CHUNK = 500;
const SEND_CONCURRENCY = 10;
// A single tick claims at most this many due rows. Without a cap, a queue
// back up (server asleep for an hour, say) would make one cron run open an FCM
// socket per recipient and run past the 120s pg_net timeout, so the whole batch
// would be retried and duplicate. The remainder is picked up next minute.
const DISPATCH_BATCH = 20;
// How far ahead a send may be queued. A year is generous for a budget alert and
// still bounds the table.
const MAX_SCHEDULE_AHEAD_MS = 366 * 24 * 60 * 60 * 1000;
// Public bucket for the picture a notification can carry. Public because the
// phone fetches it with no credential; only this function can add to it.
const PICTURE_BUCKET = "push-pictures";
const PICTURE_TYPES: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
};

type Action =
  | "directory"
  | "send"
  | "history"
  | "schedule"
  | "scheduled"
  | "cancel"
  | "picture"
  | "dispatch";

/**
 * A request the caller has to fix, as opposed to a server fault.
 *
 * Thrown rather than returned as a value: `performSend` resolves to a summary on
 * success, so an `{ error }` return type would be indistinguishable from a
 * legitimate zero-send summary at the call site. The Flutter client reads any
 * non-2xx body as `{ error }` and any 2xx body as a `SendResult`, so a validation
 * failure has to arrive as a non-2xx status to be seen at all.
 */
class BadRequestError extends Error {}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: Record<string, unknown>;
  try {
    const raw = await req.text();
    if (raw.length > MAX_BODY_LEN) return badRequest("Request body is too large");
    body = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return badRequest("Invalid JSON body");
  }

  const action = String(body.action ?? "") as Action;

  // The cron dispatcher is the one caller with no user JWT. It authenticates
  // with the internal secret instead, and is allowed to do exactly one thing:
  // send rows that are already committed to the database. It cannot enqueue,
  // cancel, read the directory or send arbitrary content, so a leaked cron
  // secret is not a broadcast primitive.
  //
  // Checked before the admin lookup because this request has no admin to find.
  if (action === "dispatch") {
    if (!body.internal) return badRequest("dispatch is internal only");
    if (!(await isInternalCaller(req, supabase))) {
      return unauthorized("Not an internal caller");
    }
    if (!readServiceAccount()) {
      return serverError("Push is not configured on this server.");
    }
    try {
      return json(await dispatchDue());
    } catch (error) {
      return serverError(
        error instanceof Error ? error.message : "Unexpected failure",
      );
    }
  }

  const admin = await resolveAdmin(req);
  if (!admin) return unauthorized("Not an admin");

  if (!readServiceAccount()) {
    return serverError("Push is not configured on this server.");
  }

  try {
    if (action === "directory") {
      return json(await buildDirectory(body.include_unreachable === true));
    }
    if (action === "history") return json(await readHistory(admin));
    if (action === "send") return json(await performSend(body, admin));
    if (action === "schedule") return json(await createSchedule(body, admin));
    if (action === "scheduled") return json(await listSchedules());
    if (action === "cancel") return json(await cancelSchedule(body));
    if (action === "picture") return json(await createPictureUpload(body));
    return badRequest("Unknown action");
  } catch (error) {
    if (error instanceof BadRequestError) return badRequest(error.message);
    return serverError(
      error instanceof Error ? error.message : "Unexpected failure",
    );
  }
});

/**
 * Returns the caller's identity when their email is an admin, else null.
 *
 * Compares against `ADMIN_EMAILS` (comma separated) rather than hardcoding a
 * single address, so a second operator can be added without a redeploy. Lower
 * cased on both sides: Supabase normalises the domain but not the local part
 * reliably enough to rely on.
 */
async function resolveAdmin(req: Request): Promise<{ email: string } | null> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;

  const allowed = (Deno.env.get("ADMIN_EMAILS") ?? "")
    .split(",")
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean);
  if (allowed.length === 0) return null;

  try {
    const { data, error } = await supabase.auth.getUser(token);
    const email = data?.user?.email;
    if (error || !email) return null;
    if (!allowed.includes(email.toLowerCase())) return null;
    return { email };
  } catch {
    return null;
  }
}

/**
 * Every account that could receive a push, with the context needed to pick one.
 *
 * Built from `push_tokens` joined to `profiles`. By default an account with no
 * token row is absent, which is what older consoles expect: they offer every
 * row for selection.
 *
 * With `includeUnreachable` the registered accounts that have no device are
 * appended with `devices: 0`. A token is unique per phone, so somebody with two
 * accounts on one phone only ever holds it under the account they signed into
 * last -- and a directory that silently drops the other account reads as "my
 * users are missing" rather than "that account has no device right now".
 */
async function buildDirectory(includeUnreachable = false): Promise<{
  users: DirectoryUser[];
  totalDevices: number;
}> {
  const [
    { data: tokenRows, error },
    { data: profiles },
    { data: settings },
  ] = await Promise.all([
    supabase.from("push_tokens").select(
      "user_id, platform, device_label, app_version, last_seen_at",
    ),
    supabase.from("profiles").select("id, display_name"),
    supabase.from("app_settings").select("user_id, notifications"),
  ]);

  if (error) throw new Error("Could not read push tokens");

  const nameByUser = new Map<string, string>();
  for (const row of profiles ?? []) {
    const id = (row as { id?: unknown }).id;
    const name = (row as { display_name?: unknown }).display_name;
    if (typeof id === "string") nameByUser.set(id, typeof name === "string" ? name : "");
  }

  const prefsByUser = new Map<string, Record<string, unknown>>();
  for (const row of settings ?? []) {
    const id = (row as { user_id?: unknown }).user_id;
    const raw = (row as { notifications?: unknown }).notifications;
    if (typeof id !== "string") continue;
    prefsByUser.set(
      id,
      raw && typeof raw === "object" && !Array.isArray(raw)
        ? (raw as Record<string, unknown>)
        : {},
    );
  }

  // One paged listing instead of a lookup per account. Null when the listing
  // fails, in which case emails fall back to the per-user lookup and the
  // unreachable accounts are simply left out rather than failing the directory.
  const accounts = await listAccounts();

  const byUser = new Map<string, DirectoryUser>();
  for (const raw of tokenRows ?? []) {
    const row = raw as {
      user_id?: unknown;
      platform?: unknown;
      device_label?: unknown;
      app_version?: unknown;
      last_seen_at?: unknown;
    };
    const userId = typeof row.user_id === "string" ? row.user_id : "";
    if (!userId) continue;

    let entry = byUser.get(userId);
    if (!entry) {
      entry = {
        userId,
        displayName: nameByUser.get(userId) ?? "",
        email: accounts
          ? accounts.get(userId)?.email ?? ""
          : await emailFor(userId),
        devices: 0,
        platforms: [],
        lastSeenAt: null,
        preferences: prefsByUser.get(userId) ?? {},
      };
      byUser.set(userId, entry);
    }

    entry.devices += 1;
    const platform = typeof row.platform === "string" ? row.platform : "unknown";
    if (!entry.platforms.includes(platform)) entry.platforms.push(platform);

    const seen = typeof row.last_seen_at === "string" ? row.last_seen_at : null;
    if (seen && (entry.lastSeenAt === null || seen > entry.lastSeenAt)) {
      entry.lastSeenAt = seen;
    }
  }

  if (includeUnreachable && accounts) {
    for (const [userId, account] of accounts) {
      if (byUser.has(userId)) continue;
      // A guest session with no device has no name, no email and nothing to
      // deliver to; listing it would only add blank rows.
      if (account.anonymous || !account.email) continue;
      byUser.set(userId, {
        userId,
        displayName: nameByUser.get(userId) ?? "",
        email: account.email,
        devices: 0,
        platforms: [],
        lastSeenAt: null,
        preferences: prefsByUser.get(userId) ?? {},
      });
    }
  }

  const users = [...byUser.values()].sort((a, b) => a.devices - b.devices);
  return {
    users,
    totalDevices: users.reduce((sum, user) => sum + user.devices, 0),
  };
}

/**
 * Every auth account, keyed by id, or null if the listing could not be read.
 *
 * Bounded at ten pages: the console is a single-operator tool for a small user
 * base, and an unbounded loop inside a request is a worse failure than a
 * truncated list.
 */
async function listAccounts(): Promise<
  Map<string, { email: string; anonymous: boolean }> | null
> {
  const PER_PAGE = 1000;
  const MAX_PAGES = 10;
  const accounts = new Map<string, { email: string; anonymous: boolean }>();
  try {
    for (let page = 1; page <= MAX_PAGES; page++) {
      const { data, error } = await supabase.auth.admin.listUsers({
        page,
        perPage: PER_PAGE,
      });
      if (error) return null;
      const batch = data?.users ?? [];
      for (const user of batch) {
        accounts.set(user.id, {
          email: typeof user.email === "string" ? user.email : "",
          anonymous: user.is_anonymous === true,
        });
      }
      if (batch.length < PER_PAGE) break;
    }
    return accounts;
  } catch {
    return null;
  }
}

type DirectoryUser = {
  userId: string;
  displayName: string;
  email: string;
  devices: number;
  platforms: string[];
  lastSeenAt: string | null;
  preferences: Record<string, unknown>;
};

/**
 * Resolves an email for display. Service-role `auth.admin` lookups are per-user
 * round trips, so only called while assembling the directory, never per send.
 */
async function emailFor(userId: string): Promise<string> {
  try {
    const { data, error } = await supabase.auth.admin.getUserById(userId);
    const email = data?.user?.email;
    return !error && typeof email === "string" ? email : "";
  } catch {
    return "";
  }
}

/**
 * A validated, send-ready request.
 *
 * Split out from the delivery work so the same validation runs whether a send
 * came from the console right now or from the dispatcher at 03:00. Validating
 * only the interactive path would let a queued row fail hours later for a
 * reason the operator could not have seen when they queued it.
 */
type SendRequest = {
  category: string;
  title: string;
  body: string;
  audience: "broadcast" | "users";
  userIds: string[];
  data: Record<string, string>;
  /**
   * Deliver to users who switched this category off in Settings.
   *
   * Off unless the operator asks for it per send. Some categories are off by
   * default in the app (daily and weekly summary), so without an override the
   * console could never send those types to anyone who has not gone into
   * Settings and switched them on.
   */
  ignoreOptOut: boolean;
};

async function performSend(
  body: Record<string, unknown>,
  admin: { email: string },
): Promise<Record<string, unknown>> {
  return deliver(parseSendRequest(body), admin.email);
}

/** Validates a raw request body into a [SendRequest]. Throws [BadRequestError]. */
function parseSendRequest(body: Record<string, unknown>): SendRequest {
  const category = String(body.category ?? "");
  const spec = PUSH_TYPES[category];
  if (!spec) {
    throw new BadRequestError(
      `Unknown category '${category}'. Known: ${Object.keys(PUSH_TYPES).join(", ")}`,
    );
  }

  const title = String(body.title ?? spec.title ?? "").slice(0, 120).trim();
  const messageBody = String(body.body ?? "").slice(0, 400).trim();
  if (!title || !messageBody) {
    throw new BadRequestError("Both title and body are required");
  }

  const audience = String(body.audience ?? "broadcast");
  if (audience !== "broadcast" && audience !== "users") {
    throw new BadRequestError("Audience must be 'broadcast' or 'users'");
  }

  const rawIds = Array.isArray(body.user_ids) ? body.user_ids : [];
  const userIds = rawIds.filter((id): id is string =>
    typeof id === "string" && id.length > 0
  );

  // A targeted send with nobody selected is a client bug or a truncated payload,
  // and rejecting it here is better than resolving "everyone reachable" by
  // accident. Broadcast is the only way to address the whole user base.
  if (audience === "users" && userIds.length === 0) {
    throw new BadRequestError("A targeted send needs at least one user id");
  }

  // Refused rather than dropped: a picture that silently goes missing is only
  // found out after the notification has reached everyone without it.
  const data = sanitizeData(body.data);
  if (data.image !== undefined && !pictureUrl(data.image)) {
    throw new BadRequestError("The picture must be an https link");
  }

  return {
    category,
    title,
    body: messageBody,
    audience,
    userIds,
    data,
    // Strictly `true`: a missing or malformed flag must never read as consent to
    // override somebody's setting.
    ignoreOptOut: body.ignore_opt_out === true,
  };
}

/**
 * Resolves recipients, sends, prunes dead tokens and writes the audit row.
 *
 * Shared by the interactive `send` action and the scheduled dispatcher so a
 * queued send is byte-for-byte the same operation as an immediate one. In
 * particular both go through `loadRecipients`, so a user's opt-out is honoured
 * when a scheduled broadcast finally fires and not merely at queue time.
 */
async function deliver(
  request: SendRequest,
  adminEmail: string,
): Promise<Record<string, unknown>> {
  const { category, title, body: messageBody, audience, data, ignoreOptOut } =
    request;
  const spec = PUSH_TYPES[category];
  const channelId = resolveChannel(category);

  // Resolved at delivery time, not queue time: a broadcast queued for Monday
  // must reach whoever has a device on Monday, which is not the same set as
  // today. `loadRecipients` then re-applies opt-outs against that same set.
  const userIds = audience === "broadcast"
    ? await allReachableUserIds()
    : request.userIds;

  if (userIds.length === 0) {
    throw new BadRequestError("No recipients matched");
  }

  const { recipients, optedOut } = await loadRecipients(
    userIds,
    spec.prefKey,
    ignoreOptOut,
  );
  if (recipients.length === 0) {
    throw new BadRequestError(
      optedOut > 0
        ? "Every selected user has turned this category off in Settings"
        : "No selected user has a registered device",
    );
  }
  const startedAt = new Date().toISOString();

  const results: { token: string; userId: string; result: Awaited<ReturnType<typeof sendMessage>> }[] = [];
  for (
    let offset = 0; offset < recipients.length; offset += BROADCAST_CHUNK
  ) {
    const chunk = recipients.slice(offset, offset + BROADCAST_CHUNK);
    const chunkResults = await sendInBatches(chunk, async (entry) => {
      const result = await sendMessage({
        token: entry.token,
        appVersion: entry.appVersion,
        data: { ...data, title, body: messageBody, category },
        android: { priority: spec.priority, ttl: spec.ttl },
      });
      return { token: entry.token, userId: entry.userId, result };
    });
    results.push(...chunkResults);
  }

  const dead = results
    .filter((entry) => !entry.result.ok && entry.result.unregistered)
    .map((entry) => entry.token);
  if (dead.length > 0) {
    await supabase.from("push_tokens").delete().in("token", dead);
  }

  const sent = results.filter((entry) => entry.result.ok).length;
  const failed = results.length - sent;
  const notifiedUsers = new Set(
    results.filter((entry) => entry.result.ok).map((entry) => entry.userId),
  ).size;

  // Resolved as a value rather than inline: `Array.prototype.find` does not narrow
  // its callback's return type, so `find(...)?.result.code` would still be typed
  // as the full `SendResult` union and would not typecheck. Selecting the entry
  // first and then narrowing its `result` is both correct and readable.
  const firstFailure = results.find((entry) => !entry.result.ok);
  const firstError = firstFailure && !firstFailure.result.ok
    ? firstFailure.result.code
    : null;

  const summary = {
    category,
    channelId,
    audience,
    title,
    body: messageBody,
    recipients: results.length,
    uniqueUsers: notifiedUsers,
    sent,
    failed,
    removedTokens: dead.length,
    optedOut,
    detail: failed > 0 ? { firstError } : null,
  };

  await supabase.from("admin_push_log").insert({
    admin_email: adminEmail,
    category,
    channel_id: channelId,
    title,
    body: messageBody,
    audience,
    recipients: results.length,
    sent,
    failed,
    removed_tokens: dead.length,
    payload_data: data,
    started_at: startedAt,
  });

  // The code is logged because `admin_push_log` only stores counts: without it a
  // send that fails for a reason other than a dead token leaves nothing behind
  // to say why.
  if (failed > 0) {
    console.warn(
      `[admin-push] ${failed} failures (first: ${firstError}), pruned ${dead.length} tokens`,
    );
  }

  return summary;
}

// ------------------------------------------------------------------ pictures

/**
 * Gives the console somewhere to put a picture, and the link it will have.
 *
 * The console uploads straight to storage with the one-time token returned
 * here, so the picture never passes through this function (whose request body
 * is capped far below the size of a photo). The name is random and chosen
 * here, so an upload can neither replace an earlier picture nor pick its path.
 */
async function createPictureUpload(
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const extension = PICTURE_TYPES[String(body.content_type ?? "image/jpeg")];
  if (!extension) {
    throw new BadRequestError("A picture must be a JPEG or a PNG");
  }
  const path = `${crypto.randomUUID()}.${extension}`;
  const bucket = supabase.storage.from(PICTURE_BUCKET);
  const { data, error } = await bucket.createSignedUploadUrl(path);
  if (error || !data?.token) {
    throw new Error("Could not prepare the picture upload");
  }
  return {
    bucket: PICTURE_BUCKET,
    path,
    token: data.token,
    url: bucket.getPublicUrl(path).data.publicUrl,
  };
}

// ---------------------------------------------------------------- scheduling

/**
 * Queues a send for the future.
 *
 * Runs the same `parseSendRequest` as an immediate send, so a category typo, an
 * over-long title or a targeted send with no recipients is rejected now, while
 * the operator is still looking at the compose sheet, rather than at 03:00 when
 * the dispatcher picks the row up.
 *
 * Recipients are deliberately not resolved here. A broadcast stores no user ids
 * at all and is expanded at delivery time, so it reaches whoever has a device
 * when it fires rather than a snapshot of today's user base.
 */
async function createSchedule(
  body: Record<string, unknown>,
  admin: { email: string },
): Promise<Record<string, unknown>> {
  const request = parseSendRequest(body);

  const sendAt = Date.parse(String(body.send_at ?? ""));
  if (Number.isNaN(sendAt)) {
    throw new BadRequestError("send_at must be an ISO 8601 timestamp");
  }
  const now = Date.now();
  if (sendAt <= now) {
    throw new BadRequestError("send_at must be in the future");
  }
  if (sendAt - now > MAX_SCHEDULE_AHEAD_MS) {
    throw new BadRequestError("send_at is more than a year away");
  }

  // Recorded for display only. `send_at` is authoritative because it is an
  // absolute instant; a zone string cannot survive a DST rule change and must
  // not be used to recompute the time.
  const timezone = String(body.timezone ?? "UTC").slice(0, 64);

  const { data, error } = await supabase
    .from("admin_scheduled_sends")
    .insert({
      admin_email: admin.email,
      category: request.category,
      title: request.title,
      body: request.body,
      audience: request.audience,
      user_ids: request.audience === "users" ? request.userIds : [],
      payload_data: request.data,
      ignore_opt_out: request.ignoreOptOut,
      send_at: new Date(sendAt).toISOString(),
      timezone,
      status: "pending",
    })
    .select("id, send_at, status, timezone")
    .single();
  if (error) throw new Error("Could not queue the send");

  return { id: data?.id ?? null, sendAt: data?.send_at ?? null, status: "pending" };
}

/** Pending sends, soonest first. Terminal rows are excluded. */
async function listSchedules(): Promise<{ entries: unknown[] }> {
  const { data, error } = await supabase
    .from("admin_scheduled_sends")
    .select(
      "id, category, title, body, audience, user_ids, send_at, timezone, status, created_at",
    )
    .eq("status", "pending")
    .order("send_at", { ascending: true })
    .limit(50);
  if (error) return { entries: [] };
  return { entries: data ?? [] };
}

/**
 * Cancels a pending send.
 *
 * Guarded on `status = 'pending'` in the update itself rather than read-then-write,
 * so a cancel racing the dispatcher cannot resurrect or double-send a row: either
 * this matches (and the row becomes 'cancelled') or the dispatcher already claimed
 * it and this matches nothing.
 */
async function cancelSchedule(
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const id = String(body.id ?? "");
  if (!id) throw new BadRequestError("id is required");

  const { data, error } = await supabase
    .from("admin_scheduled_sends")
    .update({ status: "cancelled", completed_at: new Date().toISOString() })
    .eq("id", id)
    .eq("status", "pending")
    .select("id")
    .maybeSingle();
  if (error) throw new Error("Could not cancel the send");

  if (!data) {
    throw new BadRequestError("That send is no longer pending");
  }
  return { id, status: "cancelled" };
}

/**
 * Claims and sends every row that is due.
 *
 * Claimed by flipping `pending` -> `sending` with a conditional update before any
 * FCM call, so a second tick that overlaps a slow first one cannot double-send.
 * The status is not in the table's check constraint, so it is added here.
 *
 * A row that fails is marked 'failed' and left alone rather than retried: a
 * scheduled send that is minutes late has usually lost its reason to exist, and
 * an automatic retry risks notifying people about something already resolved.
 */
async function dispatchDue(): Promise<Record<string, unknown>> {
  const { data: due, error } = await supabase
    .from("admin_scheduled_sends")
    .select(
      "id, admin_email, category, title, body, audience, user_ids, payload_data, ignore_opt_out",
    )
    .eq("status", "pending")
    .lte("send_at", new Date().toISOString())
    .order("send_at", { ascending: true })
    .limit(DISPATCH_BATCH);
  if (error) throw new Error("Could not read the send queue");

  const rows = due ?? [];
  const results: Record<string, unknown>[] = [];

  for (const raw of rows) {
    const row = raw as {
      id?: unknown;
      admin_email?: unknown;
      category?: unknown;
      title?: unknown;
      body?: unknown;
      audience?: unknown;
      user_ids?: unknown;
      payload_data?: unknown;
      ignore_opt_out?: unknown;
    };
    const id = typeof row.id === "string" ? row.id : "";
    if (!id) continue;

    // The claim. Returns no row if a concurrent tick got there first.
    const { data: claimed } = await supabase
      .from("admin_scheduled_sends")
      .update({ status: "sending" })
      .eq("id", id)
      .eq("status", "pending")
      .select("id")
      .maybeSingle();
    if (!claimed) continue;

    const now = new Date().toISOString();
    try {
      const request = parseSendRequest({
        category: row.category,
        title: row.title,
        body: row.body,
        audience: row.audience,
        user_ids: row.user_ids,
        data: row.payload_data,
        ignore_opt_out: row.ignore_opt_out,
      });
      const summary = await deliver(
        request,
        typeof row.admin_email === "string" ? row.admin_email : "unknown",
      );
      await supabase
        .from("admin_scheduled_sends")
        .update({ status: "sent", completed_at: now, result: summary })
        .eq("id", id);
      results.push({ id, status: "sent", summary });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unexpected failure";
      await supabase
        .from("admin_scheduled_sends")
        .update({ status: "failed", completed_at: now, result: { error: message } })
        .eq("id", id);
      results.push({ id, status: "failed", error: message });
    }
  }

  return { claimed: rows.length, results };
}

/** Every user id with at least one token row. */
async function allReachableUserIds(): Promise<string[]> {
  const { data, error } = await supabase.from("push_tokens").select("user_id");
  if (error) throw new Error("Could not read push tokens");
  const unique = new Set<string>();
  for (const row of data ?? []) {
    const id = (row as { user_id?: unknown }).user_id;
    if (typeof id === "string" && id) unique.add(id);
  }
  return [...unique];
}

/**
 * Expands user ids into live tokens, dropping users who opted out of this
 * category.
 *
 * The opt-out check matters here even though the console is the sender: a user
 * who turned a category off in Settings did so for a reason, and an admin
 * broadcast that ignores it is exactly the kind of thing that gets the app
 * uninstalled.
 *
 * `ignoreOptOut` is the operator's explicit, per-send override of that. With it
 * set nobody is dropped and `optedOut` is 0, since nobody was skipped.
 */
async function loadRecipients(
  userIds: string[],
  prefKey: string,
  ignoreOptOut = false,
): Promise<
  {
    recipients: { userId: string; token: string; appVersion: string | null }[];
    optedOut: number;
  }
> {
  const { data: tokenRows, error } = await supabase
    .from("push_tokens")
    .select("user_id, token, app_version")
    .in("user_id", userIds);
  if (error) throw new Error("Could not read push tokens");

  const { data: settings } = await supabase
    .from("app_settings")
    .select("user_id, notifications")
    .in("user_id", userIds);

  const optedOut = new Set<string>();
  for (const row of ignoreOptOut ? [] : settings ?? []) {
    const id = (row as { user_id?: unknown }).user_id;
    const raw = (row as { notifications?: unknown }).notifications;
    if (typeof id !== "string" || !raw || typeof raw !== "object") continue;
    if ((raw as Record<string, unknown>)[prefKey] === false) optedOut.add(id);
  }

  const recipients: {
    userId: string;
    token: string;
    appVersion: string | null;
  }[] = [];
  // Users who actually had a token row but opted out. Counting users rather than
  // subtracting token rows from requested ids is what makes the number mean
  // something: a user with three devices would otherwise inflate the opt-out
  // count by three.
  const optedOutWithTokens = new Set<string>();
  for (const row of tokenRows ?? []) {
    const id = (row as { user_id?: unknown }).user_id;
    const token = (row as { token?: unknown }).token;
    if (typeof id !== "string") continue;
    if (optedOut.has(id)) {
      optedOutWithTokens.add(id);
      continue;
    }
    if (typeof token !== "string" || token.trim().length === 0) continue;
    const version = (row as { app_version?: unknown }).app_version;
    recipients.push({
      userId: id,
      token: token.trim(),
      appVersion: typeof version === "string" ? version : null,
    });
  }
  return { recipients, optedOut: optedOutWithTokens.size };
}

async function readHistory(
  admin: { email: string },
): Promise<{ entries: unknown[] }> {
  const { data, error } = await supabase
    .from("admin_push_log")
    .select(
      "id, admin_email, category, channel_id, title, body, audience, recipients, sent, failed, removed_tokens, started_at",
    )
    .order("started_at", { ascending: false })
    .limit(50);
  if (error) return { entries: [] };
  void admin;
  return { entries: data ?? [] };
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

/** Coerces `data` to string-only, which FCM requires. */
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
