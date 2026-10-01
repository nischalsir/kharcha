import { assertEquals } from "jsr:@std/assert@1";

import {
  addDays,
  bsMonthRange,
  daysBetween,
  daysInBsMonth,
  fromBs,
  toBs,
} from "../_shared/bs_calendar.ts";

Deno.test("anchor: 1 Baisakh 2000 is 14 April 1943", () => {
  assertEquals(toBs("1943-04-14"), { year: 2000, month: 1, day: 1 });
  assertEquals(fromBs(2000, 1, 1), "1943-04-14");
});

Deno.test("1 October 2026 is 15 Asoj 2083", () => {
  assertEquals(toBs("2026-10-01"), { year: 2083, month: 6, day: 15 });
});

Deno.test("Asoj 2083 spans 17 Sep to 17 Oct 2026", () => {
  assertEquals(daysInBsMonth(2083, 6), 31);
  assertEquals(bsMonthRange(2083, 6), { start: "2026-09-17", end: "2026-10-18" });
});

Deno.test("round trips across a year boundary", () => {
  for (const iso of ["2027-04-13", "2027-04-14", "2027-04-15", "2033-04-14"]) {
    const bs = toBs(iso)!;
    assertEquals(fromBs(bs.year, bs.month, bs.day), iso);
  }
});

Deno.test("out of range dates are null, not wrong", () => {
  assertEquals(toBs("1900-01-01"), null);
  assertEquals(fromBs(2091, 1, 1), null);
  assertEquals(fromBs(2083, 6, 32), null);
});

Deno.test("day arithmetic", () => {
  assertEquals(addDays("2026-12-31", 1), "2027-01-01");
  assertEquals(daysBetween("2026-10-01", "2026-10-18"), 17);
});

Deno.test("projected years follow the app's calendar (nepali_utils)", () => {
  assertEquals(daysInBsMonth(2087, 4), 32);
  assertEquals(fromBs(2088, 1, 1), "2031-04-14");
  assertEquals(fromBs(2090, 1, 1), "2033-04-14");
});
