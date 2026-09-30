import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";

import {
  decide,
  type DecisionInput,
  DEFAULT_DECISION_CONFIG,
  fingerprintInsight,
  localHour,
} from "../_shared/notification_decision.ts";
import type { AiPushInsight } from "../_shared/ai.ts";

// The decision engine is the only thing standing between a chatty model and a
// user who turns notifications off, so it gets tested harder than anything else
// in the pipeline: every rule is a case here, not just the happy path.
Deno.test("a normal, novel, high-value insight is sent", () => {
  const decision = decide(freshInput());
  assert(decision.send);
});

Deno.test("the model declining is respected", () => {
  const decision = decide(freshInput({ shouldNotify: false }));
  assertEquals(decision, { send: false, reason: "model_declined" });
});

Deno.test("a blank message is never sent", () => {
  const decision = decide(freshInput({ message: "   " }));
  assertEquals(decision, { send: false, reason: "empty_message" });
});

Deno.test("low priority is dropped when the minimum is normal", () => {
  const decision = decide(freshInput({ priority: "low" }));
  assertEquals(decision, { send: false, reason: "priority_too_low" });
});

Deno.test("low priority is allowed when the minimum is low", () => {
  const decision = decide(freshInput({ priority: "low" }), {
    ...DEFAULT_DECISION_CONFIG,
    minPriority: "low",
  });
  assert(decision.send);
});

Deno.test("a user with too little history is skipped", () => {
  const decision = decide(freshInput({}, { hasEnoughData: false }));
  assertEquals(decision, { send: false, reason: "insufficient_data" });
});

Deno.test("a repeated fingerprint is a duplicate", () => {
  const repeated = "budget|/budgets|Budget at risk|#";
  const decision = decide(
    freshInput({}, {
      fingerprint: repeated,
      recentFingerprints: ["other", repeated],
    }),
    DEFAULT_DECISION_CONFIG,
    NOW,
  );
  assertEquals(decision, { send: false, reason: "duplicate_fingerprint" });
});

Deno.test("a fingerprint older than the dedupe window is allowed", () => {
  const repeated = "budget|/budgets|Budget at risk|#";
  const stale = Array.from(
    { length: DEFAULT_DECISION_CONFIG.dedupeWindow },
    (_, i) => `older-${i}`,
  );
  const decision = decide(
    freshInput({}, {
      fingerprint: repeated,
      recentFingerprints: [...stale, repeated],
    }),
    DEFAULT_DECISION_CONFIG,
    NOW,
  );
  assert(decision.send);
});

Deno.test("a push too soon after the last one is held back", () => {
  const decision = decide(
    freshInput({}, { lastNotifiedAt: hoursAgo(2) }),
    DEFAULT_DECISION_CONFIG,
    NOW,
  );
  assertEquals(decision, { send: false, reason: "cooldown_active" });
});

Deno.test("the global cooldown expires after its window", () => {
  const decision = decide(
    freshInput(
      {},
      {
        lastNotifiedAt: hoursAgo(
          DEFAULT_DECISION_CONFIG.minHoursBetweenPushes + 1,
        ),
      },
    ),
    DEFAULT_DECISION_CONFIG,
    NOW,
  );
  assert(decision.send);
});

Deno.test("the same topic is held back for longer", () => {
  // Past the global cooldown but inside the per-topic one, so this isolates
  // the topic rule rather than tripping the global one first.
  const decision = decide(
    freshInput(
      { topic: "budget" },
      {
        lastNotifiedAt: hoursAgo(
          DEFAULT_DECISION_CONFIG.minHoursBetweenPushes + 1,
        ),
        lastTopicNotified: { topic: "budget", at: hoursAgo(25) },
      },
    ),
    DEFAULT_DECISION_CONFIG,
    NOW,
  );
  assertEquals(decision, { send: false, reason: "topic_cooldown_active" });
});

Deno.test("a different topic is allowed once the global cooldown passes", () => {
  // The regression that motivated pairing the timestamp with its topic: with
  // a bare timestamp this wrongly blocked every topic.
  const decision = decide(
    freshInput(
      { topic: "saving" },
      {
        lastNotifiedAt: hoursAgo(
          DEFAULT_DECISION_CONFIG.minHoursBetweenPushes + 1,
        ),
        lastTopicNotified: { topic: "budget", at: hoursAgo(25) },
      },
    ),
    DEFAULT_DECISION_CONFIG,
    NOW,
  );
  assert(decision.send);
});

Deno.test("a topic cooldown that has expired is allowed", () => {
  const decision = decide(
    freshInput(
      { topic: "budget" },
      {
        lastNotifiedAt: hoursAgo(DEFAULT_DECISION_CONFIG.minHoursPerTopic + 1),
        lastTopicNotified: {
          topic: "budget",
          at: hoursAgo(DEFAULT_DECISION_CONFIG.minHoursPerTopic + 1),
        },
      },
    ),
    DEFAULT_DECISION_CONFIG,
    NOW,
  );
  assert(decision.send);
});

Deno.test("quiet hours block a push", () => {
  const decision = decide(
    freshInput({}, { inQuietHours: true }),
    DEFAULT_DECISION_CONFIG,
    NOW,
  );
  assertEquals(decision, { send: false, reason: "quiet_hours" });
});

Deno.test("quiet hours can be turned off", () => {
  const decision = decide(
    freshInput({}, { inQuietHours: true }),
    { ...DEFAULT_DECISION_CONFIG, respectQuietHours: false },
    NOW,
  );
  assert(decision.send);
});

Deno.test("quiet hours are evaluated in the device timezone", () => {
  // 16:15 UTC is 22:00 in Kathmandu (+5:45). The same instant is 16:15 for
  // anyone on UTC, which is neither quiet nor the middle of the night, so this
  // only passes if the offset is actually applied. A whole-hour offset would
  // also fail, which is the point: the app's home zone is +5:45.
  const at = Date.parse("2026-03-10T16:15:00.000Z");

  const inKathmandu = decide(
    { ...freshInput(), inQuietHours: undefined, utcOffsetMinutes: 345 },
    DEFAULT_DECISION_CONFIG,
    at,
  );
  assertEquals(inKathmandu, { send: false, reason: "quiet_hours" });

  const onUtc = decide(
    { ...freshInput(), inQuietHours: undefined, utcOffsetMinutes: 0 },
    DEFAULT_DECISION_CONFIG,
    at,
  );
  assert(onUtc.send);
});

Deno.test("a quiet hour in UTC is not quiet on the other side of the date line", () => {
  // 03:00 UTC is 08:45 in Kathmandu, so the user is up and this must not be
  // blocked even though 03:00 is deep in quiet hours on UTC. Wrapping past
  // midnight is the case a naive "add the hours" implementation gets wrong, and
  // 3 + 5.75 lands exactly on the 08:00 boundary, so it also pins the rule.
  const at = Date.parse("2026-03-10T03:00:00.000Z");

  const inKathmandu = decide(
    { ...freshInput(), inQuietHours: undefined, utcOffsetMinutes: 345 },
    DEFAULT_DECISION_CONFIG,
    at,
  );
  assert(inKathmandu.send);

  const onUtc = decide(
    { ...freshInput(), inQuietHours: undefined, utcOffsetMinutes: 0 },
    DEFAULT_DECISION_CONFIG,
    at,
  );
  assertEquals(onUtc, { send: false, reason: "quiet_hours" });
});

Deno.test("an unreported timezone falls back to UTC rather than skipping quiet hours", () => {
  // The cron fires at a fixed UTC time. Falling back to UTC keeps the window
  // meaningful; treating "unknown" as "never quiet" would let the 22:00-08:00
  // job wake people up.
  const at = Date.parse("2026-03-10T23:30:00.000Z");

  for (const utcOffsetMinutes of [null, undefined]) {
    const decision = decide(
      { ...freshInput(), inQuietHours: undefined, utcOffsetMinutes },
      DEFAULT_DECISION_CONFIG,
      at,
    );
    assertEquals(decision, { send: false, reason: "quiet_hours" });
  }
});

Deno.test("localHour reports the hour where the user is", () => {
  const at = new Date("2026-03-10T16:15:00.000Z");
  assertEquals(localHour(at, 0), 16);
  assertEquals(localHour(at, 345), 22);
  // Negative offsets, i.e. a device west of UTC.
  assertEquals(localHour(new Date("2026-03-10T02:00:00.000Z"), -300), 21);
  // Unknown falls through to UTC.
  assertEquals(localHour(at, null), 16);
  assertEquals(localHour(at, Number.NaN), 16);
});

Deno.test("a missing lastNotifiedAt is not treated as a cooldown", () => {
  const decision = decide(
    freshInput({}, { lastNotifiedAt: null }),
    DEFAULT_DECISION_CONFIG,
    NOW,
  );
  assert(decision.send);
});

Deno.test("a malformed lastNotifiedAt is not treated as a cooldown", () => {
  const decision = decide(
    freshInput({}, { lastNotifiedAt: "not-a-date" }),
    DEFAULT_DECISION_CONFIG,
    NOW,
  );
  assert(decision.send);
});

// --------------------------------------------------------------- fingerprinting

Deno.test("the same message on two days has one fingerprint", () => {
  const yesterday = insight({ message: "You spent NPR 13,325 this month" });
  const today = insight({ message: "You spent NPR 13,924 this month" });
  assertEquals(
    fingerprintInsight(yesterday),
    fingerprintInsight(today),
    "a few hundred rupees of drift must not read as a new insight",
  );
});

Deno.test("a different magnitude keeps a different fingerprint", () => {
  const small = insight({ message: "You spent NPR 13,325 this month" });
  const large = insight({ message: "You spent NPR 81,400 this month" });
  assertNotEquals(fingerprintInsight(small), fingerprintInsight(large));
});

Deno.test("a different topic keeps a different fingerprint", () => {
  const budget = insight({ topic: "budget" });
  const saving = insight({ topic: "saving" });
  assertNotEquals(fingerprintInsight(budget), fingerprintInsight(saving));
});

Deno.test("a different route keeps a different fingerprint", () => {
  const home = insight({ deepLink: "/" });
  const budgets = insight({ deepLink: "/budgets" });
  assertNotEquals(fingerprintInsight(home), fingerprintInsight(budgets));
});

// ------------------------------------------------------------------- helpers

// A fixed clock: the cooldown rules are pure arithmetic on timestamps, and
// using the real clock would make "2 hours ago" mean something different
// depending on when the suite runs.
const NOW = Date.parse("2026-03-10T12:00:00.000Z");

function hoursAgo(hours: number): string {
  return new Date(NOW - hours * 60 * 60 * 1000).toISOString();
}

function insight(overrides: Partial<AiPushInsight> = {}): AiPushInsight {
  return {
    shouldNotify: true,
    title: "Budget at risk",
    message: "You spent NPR 13,325 this month",
    topic: "budget",
    priority: "high",
    deepLink: "/budgets",
    promptVersion: "finance-push-v1",
    ...overrides,
  };
}

function freshInput(
  insightOverrides: Partial<AiPushInsight> = {},
  inputOverrides: Partial<DecisionInput> = {},
): DecisionInput {
  return {
    insight: insight(insightOverrides),
    fingerprint: "fingerprint",
    lastNotifiedAt: null,
    recentFingerprints: [],
    lastTopicNotified: null,
    hasEnoughData: true,
    inQuietHours: false,
    ...inputOverrides,
  };
}
