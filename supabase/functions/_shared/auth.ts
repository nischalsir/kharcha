// Shared Edge Function helpers: JWT verification, CORS, JSON, and a small
// constant-time-ish string compare.
//
// Kept deliberately dependency-free (Supabase's Edge runtime verifies JWTs
// before the function runs when `verify_jwt` is on, and the extra `getUser`
// call here is what lets these helpers work in unit tests and in the
// service-to-service send path where there is no user JWT at all).
import { corsHeaders } from "./cors.ts";

export { corsHeaders };

/**
 * The sliver of the Supabase client these helpers need. Declared structurally
 * so this module stays free of a supabase-js import, which is what lets it be
 * unit tested without a client.
 */
export interface SupabaseClientLike {
  from(table: string): {
    select(columns: string): {
      maybeSingle(): PromiseLike<{ data: unknown; error: unknown }>;
    };
  };
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function badRequest(message: string): Response {
  return json({ error: message }, 400);
}

export function serverError(message: string): Response {
  return json({ error: message }, 500);
}

export function unauthorized(message = "Not authenticated"): Response {
  return json({ error: message }, 401);
}

/** Extracts a bearer token from the Authorization header, or null. */
export function bearerToken(req: Request): string | null {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  return token.length > 0 ? token : null;
}

/**
 * Resolves the caller's user id from a verified bearer token.
 *
 * Uses the service-role client with an explicit Authorization override so the
 * lookup is authoritative: the anon client would honour a token that has been
 * revoked in the same way the app does, which is what we want.
 *
 * Returns null when the token is missing, expired or invalid.
 */
export async function getUser(req: Request): Promise<{ id: string } | null> {
  const token = bearerToken(req);
  if (!token) return null;

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return null;

  try {
    const { createClient } = await import("npm:@supabase/supabase-js@2");
    const client = createClient(url, serviceKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false },
    });
    const { data, error } = await client.auth.getUser(token);
    if (error || !data.user) return null;
    return { id: data.user.id };
  } catch {
    return null;
  }
}

/**
 * Constant-time-ish comparison of a presented secret against an expected one.
 *
 * Length is compared first: length is not secret, and short-circuiting there
 * avoids leaking timing information through the loop.
 */
export function secretMatches(
  provided: string | null,
  expected: string | null,
): boolean {
  if (!expected) return false;
  const value = (provided ?? "").trim();
  if (value.length === 0) return false;
  if (value.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) {
    diff |= value.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}

/**
 * The shared secret that lets pg_cron invoke a server-to-server path.
 *
 * Read from `ai_push_worker` rather than from the function environment on
 * purpose. The database has to know the value anyway, because the cron job is
 * the thing sending it; keeping the only copy in one place means rotating it is
 * a single UPDATE and there is no window where the two sides disagree and every
 * scheduled run silently 401s. The table is service-role only, so this is not a
 * new exposure.
 */
export async function loadInternalSecret(
  supabase: SupabaseClientLike,
): Promise<string | null> {
  try {
    const { data, error } = await supabase
      .from("ai_push_worker")
      .select("internal_secret")
      .maybeSingle();
    if (error) return null;
    const value = (data as { internal_secret?: unknown } | null)
      ?.internal_secret;
    return typeof value === "string" && value.length > 0 ? value : null;
  } catch {
    return null;
  }
}

/** True when the caller presented the internal secret and no user JWT. */
export async function isInternalCaller(
  req: Request,
  supabase: SupabaseClientLike,
): Promise<boolean> {
  const expected = await loadInternalSecret(supabase);
  if (!expected) return false;
  return secretMatches(req.headers.get("x-kharcha-internal-secret"), expected);
}
