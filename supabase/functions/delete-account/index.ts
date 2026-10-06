// Deletes the caller's own account, and everything kept for it.
//
// Only ever the account the request is signed in as: the id comes from the
// verified token, never from the request body, so nobody can be deleted by
// someone else. The body has to say so in words (`{"confirm":"DELETE"}`), so
// a stray or replayed call to this address does nothing.
//
// What goes:
//   1. every file in the account's folder of the private bucket (receipts,
//      item pictures, payment QRs, backups, the profile picture);
//   2. the account itself. Every table that holds its rows refers to it with
//      ON DELETE CASCADE, so they go with it;
//   3. a household left with nobody in it. One that still has members stays
//      theirs: its entries are kept, without this account's name on them.
//
// The service role is used only for those three steps, each scoped to the
// caller's id.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

import {
  badRequest,
  corsHeaders,
  getUser,
  json,
  serverError,
  unauthorized,
} from "../_shared/auth.ts";

const BUCKET = "kharcha-files";
const PAGE = 1000;
const MAX_DEPTH = 4;
const REMOVE_CHUNK = 100;

/** Every file under `prefix`, however deep the folders the app makes go. */
export async function listFiles(
  db: SupabaseClient,
  prefix: string,
  depth = 0,
): Promise<string[]> {
  if (depth > MAX_DEPTH) return [];
  const files: string[] = [];
  for (let offset = 0;; offset += PAGE) {
    const { data, error } = await db.storage.from(BUCKET).list(prefix, {
      limit: PAGE,
      offset,
    });
    if (error) throw new Error(`Could not list ${prefix}: ${error.message}`);
    const entries = data ?? [];
    for (const entry of entries) {
      const path = `${prefix}/${entry.name}`;
      // A folder comes back as an entry with no id.
      if (entry.id === null) {
        files.push(...await listFiles(db, path, depth + 1));
      } else {
        files.push(path);
      }
    }
    if (entries.length < PAGE) break;
  }
  return files;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const user = await getUser(req);
  if (!user) return unauthorized();

  let body: { confirm?: unknown };
  try {
    body = await req.json();
  } catch {
    return badRequest("Invalid JSON body");
  }
  if (body?.confirm !== "DELETE") {
    return badRequest("Deleting an account has to be confirmed");
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return serverError("Server is not configured");
  const db = createClient(url, serviceKey, {
    auth: { persistSession: false },
  });

  try {
    // The households this account is in, looked up before it is gone.
    const { data: memberships } = await db
      .from("household_members")
      .select("household_id")
      .eq("user_id", user.id);
    const households = [
      ...new Set(
        ((memberships ?? []) as Array<{ household_id?: unknown }>)
          .map((row) => row.household_id)
          .filter((id): id is string => typeof id === "string"),
      ),
    ];

    // Files first: once the account is gone nothing says whose they were.
    const files = await listFiles(db, user.id);
    for (let i = 0; i < files.length; i += REMOVE_CHUNK) {
      const { error } = await db.storage.from(BUCKET).remove(
        files.slice(i, i + REMOVE_CHUNK),
      );
      if (error) throw new Error(`Could not remove files: ${error.message}`);
    }

    const { error: deleteError } = await db.auth.admin.deleteUser(user.id);
    if (deleteError) {
      throw new Error(`Could not delete the account: ${deleteError.message}`);
    }

    // Best effort: an empty household nobody can reach is only clutter.
    for (const id of households) {
      const { count } = await db
        .from("household_members")
        .select("household_id", { count: "exact", head: true })
        .eq("household_id", id);
      if (count === 0) await db.from("households").delete().eq("id", id);
    }

    return json({ deleted: true, files: files.length });
  } catch (error) {
    console.error("delete-account failed", user.id, String(error));
    return serverError(
      "The account could not be deleted. Nothing was removed that cannot be " +
        "tried again.",
    );
  }
});
