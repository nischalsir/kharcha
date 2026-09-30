import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  isInternalCaller,
  loadInternalSecret,
  secretMatches,
  type SupabaseClientLike,
} from "../_shared/auth.ts";

// The shared secret is the only thing protecting an endpoint that can notify
// every user in the app, so it gets tested at the level of "can a caller who
// should not be allowed through get through".

const SECRET = "a".repeat(64);

/** A client that returns a fixed secret, or an error, or nothing. */
function client(
  secret: unknown,
  options: { error?: unknown } = {},
): SupabaseClientLike {
  return {
    from(table: string) {
      assertEquals(table, "ai_push_worker");
      return {
        select(columns: string) {
          assertEquals(columns, "internal_secret");
          return {
            maybeSingle: () =>
              Promise.resolve(
                options.error ? { data: null, error: options.error } : {
                  data: secret === undefined
                    ? null
                    : { internal_secret: secret },
                  error: null,
                },
              ),
          };
        },
      };
    },
  };
}

function request(headers: Record<string, string>): Request {
  return new Request("https://example.test/functions/v1/ai-push-digest", {
    headers,
  });
}

Deno.test("a correct secret is accepted", async () => {
  const allowed = await isInternalCaller(
    request({ "x-kharcha-internal-secret": SECRET }),
    client(SECRET),
  );
  assert(allowed);
});

Deno.test("a wrong secret is refused", async () => {
  const allowed = await isInternalCaller(
    request({ "x-kharcha-internal-secret": "b".repeat(64) }),
    client(SECRET),
  );
  assertEquals(allowed, false);
});

Deno.test("a missing header is refused", async () => {
  const allowed = await isInternalCaller(request({}), client(SECRET));
  assertEquals(allowed, false);
});

Deno.test("a prefix of the secret is refused", async () => {
  // The whole point of the length pre-check: a truncated value must not pass.
  const allowed = await isInternalCaller(
    request({ "x-kharcha-internal-secret": SECRET.slice(0, 32) }),
    client(SECRET),
  );
  assertEquals(allowed, false);
});

Deno.test("whitespace around the header is tolerated, not treated as extra", async () => {
  const allowed = await isInternalCaller(
    request({ "x-kharcha-internal-secret": `  ${SECRET}  ` }),
    client(SECRET),
  );
  assert(allowed);
});

Deno.test("an unset secret refuses everyone rather than allowing everyone", async () => {
  // The failure mode that matters: a missing row must fail closed. Treating
  // "no secret configured" as "no auth required" would expose every user.
  const unusable = [
    client(undefined),
    client(""),
    client(undefined, { error: "boom" }),
  ];
  for (const supabase of unusable) {
    const allowed = await isInternalCaller(
      request({ "x-kharcha-internal-secret": SECRET }),
      supabase,
    );
    assertEquals(allowed, false);
  }
});

Deno.test("a client that throws does not become an open door", async () => {
  const broken: SupabaseClientLike = {
    from() {
      throw new Error("network down");
    },
  };
  const allowed = await isInternalCaller(
    request({ "x-kharcha-internal-secret": SECRET }),
    broken,
  );
  assertEquals(allowed, false);
});

Deno.test("loadInternalSecret returns null on anything unusable", async () => {
  assertEquals(await loadInternalSecret(client(SECRET)), SECRET);
  assertEquals(await loadInternalSecret(client(undefined)), null);
  assertEquals(await loadInternalSecret(client(42)), null);
  assertEquals(
    await loadInternalSecret(client(undefined, { error: "nope" })),
    null,
  );
});

Deno.test("secretMatches fails closed on an empty expectation", () => {
  assertEquals(secretMatches("anything", ""), false);
  assertEquals(secretMatches("anything", null), false);
  assertEquals(secretMatches(null, SECRET), false);
  assertEquals(secretMatches(SECRET, SECRET), true);
});
