import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";

import { fallbackBuddyMessage } from "../_shared/ai.ts";
import {
  DAY_ANGLES,
  dayPart,
  dueSlot,
  localTime,
  slotSeed,
} from "../_shared/buddy_schedule.ts";
import { buildBuddyUserPrompt } from "../_shared/prompt.ts";

const NEPAL = 345;

Deno.test("each stretch of the day has its own part", () => {
  assertEquals(dayPart(9), "late_morning");
  assertEquals(dayPart(10), "late_morning");
  assertEquals(dayPart(11), "midday");
  assertEquals(dayPart(13), "midday");
  assertEquals(dayPart(14), "afternoon");
  assertEquals(dayPart(16), "afternoon");
  assertEquals(dayPart(17), "evening");
  assertEquals(dayPart(20), "evening");
});

Deno.test("the morning line is not the same every day", () => {
  // The seed used to be the same number every morning, so the canned
  // greeting never changed.
  const lines = new Set<string>();
  for (let day = 1; day <= 14; day++) {
    const date = `2026-10-${String(day).padStart(2, "0")}`;
    const key = `buddy:${date}:morning`;
    lines.add(fallbackBuddyMessage("morning", slotSeed("user-a", key)).message);
  }
  assert(lines.size >= 4, `only ${lines.size} different mornings in 14 days`);
});

Deno.test("a canned line that was just sent is skipped", () => {
  const seed = 3;
  const first = fallbackBuddyMessage("night", seed);
  const second = fallbackBuddyMessage("night", seed, {
    recent: [first.message],
  });
  assertNotEquals(second.message, first.message);

  // Punctuation and case do not make it a different line.
  const third = fallbackBuddyMessage("night", seed, {
    recent: [first.message.toUpperCase().replace(/[.!]/g, "")],
  });
  assertNotEquals(third.message, first.message);
});

Deno.test("a full day of canned lines has no repeats", () => {
  const sent: string[] = [];
  const slots: Array<["morning" | "day" | "night", string | null]> = [
    ["morning", null],
    ["day", "late_morning"],
    ["day", "midday"],
    ["day", "afternoon"],
    ["day", "evening"],
    ["night", null],
  ];
  for (const [slot, part] of slots) {
    const line = fallbackBuddyMessage(slot, 7, { part, recent: sent });
    assert(!sent.includes(line.message), `repeated: ${line.message}`);
    sent.unshift(line.message);
  }
  assertEquals(sent.length, 6);
});

Deno.test("daytime lines belong to their part of the day", () => {
  const midday = new Set<string>();
  const evening = new Set<string>();
  for (let seed = 0; seed < 20; seed++) {
    midday.add(fallbackBuddyMessage("day", seed, { part: "midday" }).message);
    evening.add(fallbackBuddyMessage("day", seed, { part: "evening" }).message);
  }
  for (const line of midday) assert(!evening.has(line), `shared: ${line}`);
  assert(midday.size >= 4);
  assert(evening.size >= 4);
});

Deno.test("an unknown part still produces a line", () => {
  const line = fallbackBuddyMessage("day", 1, { part: "teatime" });
  assert(line.message.length > 0);
  assertEquals(line.source, "fallback");
});

Deno.test("two daytime slots on one day get different seeds", () => {
  const local = localTime(new Date("2026-10-01T05:15:00Z"), NEPAL);
  const a = slotSeed("user-a", `buddy:${local.date}:day0`);
  const b = slotSeed("user-a", `buddy:${local.date}:day1`);
  assertNotEquals(a, b);
  assert(DAY_ANGLES.length >= 6);
  // dueSlot keys are what the seeds are built from.
  assertEquals(dueSlot("u1", localTime(new Date("2026-10-01T00:15:00Z"), NEPAL), 2)?.key,
    "buddy:2026-10-01:morning");
});

Deno.test("the prompt carries the time of day, the angle and recent lines", () => {
  const prompt = JSON.parse(buildBuddyUserPrompt({
    slot: "day",
    name: "Nischal Pandey",
    currency: "NPR",
    incomeThisMonth: 1000,
    expenseThisMonth: 400,
    expenseToday: 50,
    topCategory: "Food",
    weekday: "Thursday",
    timeOfDay: "afternoon",
    localTime: "15:30",
    angle: "tiny_challenge",
    recent: ["Log your lunch"],
  }));
  assertEquals(prompt.time_of_day, "afternoon");
  assertEquals(prompt.local_time, "15:30");
  assertEquals(prompt.angle, "tiny_challenge");
  assertEquals(prompt.avoid_repeating, ["Log your lunch"]);
  assertEquals(prompt.first_name, "Nischal");

  // Greetings have no angle: they are always a greeting.
  const morning = JSON.parse(buildBuddyUserPrompt({
    slot: "morning",
    name: null,
    currency: "NPR",
    incomeThisMonth: 0,
    expenseThisMonth: 0,
    expenseToday: 0,
    topCategory: null,
    weekday: "Thursday",
    angle: "praise",
  }));
  assertEquals(morning.angle, null);
  assertEquals(morning.avoid_repeating, []);
});
