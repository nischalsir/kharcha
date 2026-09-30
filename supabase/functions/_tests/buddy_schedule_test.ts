import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  daytimeQuarters,
  dueSlot,
  localTime,
} from "../_shared/buddy_schedule.ts";

const NEPAL = 345;

Deno.test("06:00 Nepal is the morning slot", () => {
  // 00:15 UTC == 06:00 NPT.
  const local = localTime(new Date("2026-10-01T00:15:00Z"), NEPAL);
  assertEquals(local.hour, 6);
  assertEquals(local.minute, 0);
  assertEquals(dueSlot("u1", local, 2)?.slot, "morning");
  assertEquals(dueSlot("u1", local, 2)?.key, "buddy:2026-10-01:morning");
});

Deno.test("22:00 Nepal is the night slot", () => {
  const local = localTime(new Date("2026-10-01T16:15:00Z"), NEPAL);
  assertEquals(dueSlot("u1", local, 2)?.slot, "night");
});

Deno.test("nothing is due at 03:00", () => {
  const local = localTime(new Date("2026-09-30T21:15:00Z"), NEPAL);
  assertEquals(local.hour, 3);
  assertEquals(dueSlot("u1", local, 2), null);
});

Deno.test("daytime slots are stable, spaced and inside 09:00-21:00", () => {
  const a = daytimeQuarters("user-a", "2026-10-01", 3);
  assertEquals(a, daytimeQuarters("user-a", "2026-10-01", 3));
  assertEquals(a.length, 3);
  for (let i = 0; i < a.length; i++) {
    assert(a[i] >= 36 && a[i] < 84, `quarter ${a[i]} out of range`);
    if (i > 0) assert(a[i] - a[i - 1] >= 4, "slots too close");
  }
});

Deno.test("daytime slots differ between days", () => {
  const days = new Set<string>();
  for (let d = 1; d <= 10; d++) {
    days.add(daytimeQuarters("user-a", `2026-10-${String(d).padStart(2, "0")}`, 2).join());
  }
  assert(days.size > 1);
});

Deno.test("each daytime slot fires exactly once in a day", () => {
  const quarters = daytimeQuarters("u9", "2026-10-01", 2);
  let fired = 0;
  for (let q = 0; q < 96; q++) {
    const local = {
      date: "2026-10-01",
      hour: Math.floor(q / 4),
      minute: (q % 4) * 15,
      quarter: q,
    };
    if (dueSlot("u9", local, 2)?.slot === "day") fired++;
  }
  assertEquals(fired, quarters.length);
});
