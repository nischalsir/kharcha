// Registers (or refreshes) a device's FCM token against the caller's account.
//
// Why this is a function and not a direct PostgREST insert: a client-supplied
// `user_id` cannot be trusted to equal the caller's. Doing the write here, with
// the user id taken from the verified JWT, means a client cannot register a
// token onto someone else's account even if it crafts the request by hand.
//
// The FCM token is also unique per device, so re-registering after a sign-out /
// sign-in or an app reinstall *moves* the token to the current account rather
// than duplicating it. That is what makes "notifications keep working after
// reinstall and after logging back in" true without any client bookkeeping.
import { createClient } from "jsr:@supabase/supabase-js@2";

import { corsHeaders, json } from "../_shared/cors.ts";
import { badRequest, getUser, serverError } from "../_shared/auth.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

// FCM registration tokens are long, opaque and occasionally contain the
// separators below. Rather than encode a fragile exact grammar, reject only
// what cannot be a token: blank, absurdly long, or containing characters FCM
// never emits (whitespace, commas, quotes, angle brackets).
const MAX_TOKEN_LENGTH = 4096;
const INVALID_TOKEN_CHARS = /[\s,;<>"'\\]/;

function normalizePlatform(value: unknown): string {
  const platform = typeof value === "string" ? value.trim().toLowerCase() : "";
  if (platform === "" || platform === "android") return "android";
  return platform.slice(0, 32);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const user = await getUser(req);
  if (!user) return json({ error: "Not authenticated" }, 401);

  let body;
  try {
    body = await req.json();
  } catch {
    return badRequest("Invalid JSON body");
  }

  const token = typeof body?.token === "string" ? body.token.trim() : "";
  if (!token) return badRequest("Missing token");
  if (token.length > MAX_TOKEN_LENGTH) return badRequest("Token is too long");
  if (INVALID_TOKEN_CHARS.test(token)) return badRequest("Malformed token");

  const userId = user.id;
  const platform = normalizePlatform(body?.platform);
  const appVersion = typeof body?.app_version === "string"
    ? body.app_version.slice(0, 32)
    : null;
  const deviceLabel = typeof body?.device_label === "string"
    ? body.device_label.slice(0, 80)
    : null;

  try {
    // A token belongs to exactly one device, so it can only belong to one user.
    // If it is currently registered elsewhere, that row is reassigned here.
    const { data: existing, error: lookupError } = await supabase
      .from("push_tokens")
      .select("id, user_id")
      .eq("token", token)
      .maybeSingle();

    if (lookupError) return serverError("Could not read the token registry.");

    let row;
    if (existing) {
      const { data, error } = await supabase
        .from("push_tokens")
        .update({
          user_id: userId,
          platform,
          app_version: appVersion,
          device_label: deviceLabel,
          last_seen_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", existing.id)
        .select("id, user_id, platform, last_seen_at")
        .single();
      if (error) return serverError("Could not refresh the token.");
      row = data;
    } else {
      const { data, error } = await supabase
        .from("push_tokens")
        .insert({
          user_id: userId,
          token,
          platform,
          app_version: appVersion,
          device_label: deviceLabel,
        })
        .select("id, user_id, platform, last_seen_at")
        .single();
      if (error) {
        // Lost a race against a concurrent registration of the same token.
        // The unique index did its job; report conflict so the client can retry.
        if (error.code === "23505") {
          return json({ error: "Token registration conflicted" }, 409);
        }
        return serverError("Could not register the token.");
      }
      row = data;
    }

    return json({
      registered: true,
      tokenId: row.id,
      platform: row.platform,
      lastSeenAt: row.last_seen_at,
      // True when this token was previously registered to a different account,
      // so the app can tell the user their notifications moved accounts.
      reassigned: Boolean(existing && existing.user_id !== userId),
    });
  } catch (error) {
    console.error("register-push-token failed", error);
    return serverError("Could not register the token.");
  }
});
