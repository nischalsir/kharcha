// Bikram Sambat (BS) calendar arithmetic for the server.
//
// Budgets are stored per BS month and pasal accounts settle at BS month end, so
// the reminder worker has to know where a BS month starts and ends. BS month
// lengths are not computable from a formula; they come from the published
// calendar, taken here from `nepali-date-converter` (BS 2000-2090). Only its
// data table is used: the conversion itself is plain UTC day counting below,
// so the result never depends on the runtime's local timezone.
//
// Dates on both sides are calendar dates, never instants. Gregorian dates are
// ISO `YYYY-MM-DD` strings.
import { dateConfigMap } from "npm:nepali-date-converter@3.4.0";

export interface BsDate {
  year: number;
  /** 1 (Baisakh) .. 12 (Chaitra). */
  month: number;
  day: number;
}

/** Display names, matching the app's English month labels. */
export const BS_MONTH_NAMES = [
  "Baisakh",
  "Jestha",
  "Asar",
  "Shrawan",
  "Bhadra",
  "Asoj",
  "Kartik",
  "Mangsir",
  "Poush",
  "Magh",
  "Falgun",
  "Chaitra",
];

// Keys of each year's entry in dateConfigMap, in calendar order.
const SOURCE_MONTH_KEYS = [
  "Baisakh",
  "Jestha",
  "Asar",
  "Shrawan",
  "Bhadra",
  "Aswin",
  "Kartik",
  "Mangsir",
  "Poush",
  "Magh",
  "Falgun",
  "Chaitra",
];

/** 1 Baisakh 2000 BS. */
const ANCHOR_UTC = Date.UTC(1943, 3, 14);
const DAY_MS = 86_400_000;

const TABLE = dateConfigMap as unknown as Record<
  string,
  Record<string, number>
>;

export const BS_FIRST_YEAR = 2000;
export const BS_LAST_YEAR = 2090;

/** Days in one BS month, or 0 outside the supported range. */
export function daysInBsMonth(year: number, month: number): number {
  const row = TABLE[String(year)];
  if (!row || month < 1 || month > 12) return 0;
  return row[SOURCE_MONTH_KEYS[month - 1]] ?? 0;
}

function isoToDayNumber(iso: string): number | null {
  const ms = Date.parse(`${iso}T00:00:00Z`);
  return Number.isFinite(ms) ? Math.round(ms / DAY_MS) : null;
}

function dayNumberToIso(day: number): string {
  return new Date(day * DAY_MS).toISOString().slice(0, 10);
}

/** Adds whole days to an ISO date. */
export function addDays(iso: string, days: number): string {
  const day = isoToDayNumber(iso);
  if (day === null) return iso;
  return dayNumberToIso(day + days);
}

/** Whole days from `from` to `to` (positive when `to` is later). */
export function daysBetween(from: string, to: string): number {
  const a = isoToDayNumber(from);
  const b = isoToDayNumber(to);
  if (a === null || b === null) return 0;
  return b - a;
}

/** Converts a Gregorian date to BS, or null outside BS 2000-2090. */
export function toBs(iso: string): BsDate | null {
  const day = isoToDayNumber(iso);
  if (day === null) return null;
  let remaining = day - Math.round(ANCHOR_UTC / DAY_MS);
  if (remaining < 0) return null;
  for (let year = BS_FIRST_YEAR; year <= BS_LAST_YEAR; year++) {
    for (let month = 1; month <= 12; month++) {
      const length = daysInBsMonth(year, month);
      if (remaining < length) return { year, month, day: remaining + 1 };
      remaining -= length;
    }
  }
  return null;
}

/** Converts a BS date to Gregorian, or null outside the supported range. */
export function fromBs(year: number, month: number, day: number): string | null {
  if (year < BS_FIRST_YEAR || year > BS_LAST_YEAR) return null;
  if (day < 1 || day > daysInBsMonth(year, month)) return null;
  let offset = 0;
  for (let y = BS_FIRST_YEAR; y < year; y++) {
    for (let m = 1; m <= 12; m++) offset += daysInBsMonth(y, m);
  }
  for (let m = 1; m < month; m++) offset += daysInBsMonth(year, m);
  return dayNumberToIso(Math.round(ANCHOR_UTC / DAY_MS) + offset + day - 1);
}

/**
 * The Gregorian span of one BS month: `start` is its first day and `end` the
 * first day of the following month (exclusive).
 */
export function bsMonthRange(
  year: number,
  month: number,
): { start: string; end: string } | null {
  const start = fromBs(year, month, 1);
  if (!start) return null;
  return { start, end: addDays(start, daysInBsMonth(year, month)) };
}
