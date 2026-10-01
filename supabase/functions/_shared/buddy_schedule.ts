// When the flame's "daily buddy" pushes go out, per user, in their local time.
//
//   06:00        good morning
//   09:00-20:45  N nudges at quarter-hours picked per user per day
//   22:00        good night
//
// The worker runs every 15 minutes, so every check is "does the current local
// quarter-hour match a slot". Daytime slots are derived from a hash of
// (user, local date) instead of being stored: they are random-looking, differ
// per user and per day, and are stable across the runs of one day without a
// table to keep them in.

export type BuddySlot = "morning" | "day" | "night";

export const MORNING_HOUR = 6;
export const NIGHT_HOUR = 22;
const DAY_START_QUARTER = 9 * 4; // 09:00
const DAY_END_QUARTER = 21 * 4; // 21:00, exclusive

export interface LocalTime {
  /** YYYY-MM-DD in the user's local calendar. */
  date: string;
  hour: number;
  minute: number;
  /** 0..95, the quarter-hour of the local day. */
  quarter: number;
}

/**
 * Local wall-clock for a device offset in minutes east of UTC. A missing
 * offset falls back to UTC, the same convention notification_decision.ts uses.
 */
export function localTime(now: Date, utcOffsetMinutes: number | null): LocalTime {
  const offset = typeof utcOffsetMinutes === "number" &&
      Number.isFinite(utcOffsetMinutes)
    ? utcOffsetMinutes
    : 0;
  const shifted = new Date(now.getTime() + offset * 60_000);
  const hour = shifted.getUTCHours();
  const minute = shifted.getUTCMinutes();
  return {
    date: shifted.toISOString().slice(0, 10),
    hour,
    minute,
    quarter: hour * 4 + Math.floor(minute / 15),
  };
}

/** The stretch of the day a daytime nudge lands in. */
export type DayPart = "late_morning" | "midday" | "afternoon" | "evening";

/**
 * Which part of the day a local hour belongs to, so a nudge at 10:00 does not
 * read like one at 19:00.
 */
export function dayPart(hour: number): DayPart {
  if (hour < 11) return "late_morning";
  if (hour < 14) return "midday";
  if (hour < 17) return "afternoon";
  return "evening";
}

/** What a daytime nudge is about. One is chosen per slot so they differ. */
export const DAY_ANGLES = [
  "saving_tip",
  "log_reminder",
  "month_progress",
  "top_category",
  "tiny_challenge",
  "praise",
  "money_fact",
  "budget_check",
] as const;
export type DayAngle = (typeof DAY_ANGLES)[number];

/**
 * A number that differs per user, per day and per slot. Used to choose the
 * angle and the canned line, so neither repeats from one slot to the next.
 */
export function slotSeed(userId: string, key: string): number {
  return hash(`${userId}|${key}`);
}

/** FNV-1a, enough to spread slots; not used for anything security related. */
function hash(text: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/**
 * The daytime quarter-hours for one user on one local day, sorted, distinct,
 * and at least an hour apart so two nudges never land back to back.
 */
export function daytimeQuarters(
  userId: string,
  date: string,
  count: number,
): number[] {
  const span = DAY_END_QUARTER - DAY_START_QUARTER;
  const picked: number[] = [];
  let seed = hash(`${userId}|${date}`);
  for (let attempt = 0; picked.length < count && attempt < 50; attempt++) {
    seed = hash(`${seed}`);
    const quarter = DAY_START_QUARTER + (seed % span);
    if (picked.every((q) => Math.abs(q - quarter) >= 4)) picked.push(quarter);
  }
  return picked.sort((a, b) => a - b);
}

/**
 * The slot due right now for this user, or null. Includes a stable key used
 * to make sure a slot is delivered at most once even if a run is retried.
 */
export function dueSlot(
  userId: string,
  local: LocalTime,
  daytimeCount: number,
): { slot: BuddySlot; key: string } | null {
  if (local.hour === MORNING_HOUR && local.minute < 15) {
    return { slot: "morning", key: `buddy:${local.date}:morning` };
  }
  if (local.hour === NIGHT_HOUR && local.minute < 15) {
    return { slot: "night", key: `buddy:${local.date}:night` };
  }
  const index = daytimeQuarters(userId, local.date, daytimeCount).indexOf(
    local.quarter,
  );
  if (index >= 0) {
    return { slot: "day", key: `buddy:${local.date}:day${index}` };
  }
  return null;
}
