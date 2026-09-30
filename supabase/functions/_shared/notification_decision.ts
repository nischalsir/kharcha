// Decides whether a validated AI insight is worth interrupting the user for.
//
// Deliberately separate from the prompt and the model. The model is allowed to
// be wrong in the direction of "sounds interesting"; this module is the
// deterministic gate that keeps the notification feed trustworthy. Every rule
// here is a hard stop that survives a prompt regression, because a bad prompt
// revision would otherwise quietly start spamming every user.
//
// Applied in order; the first failure wins and is returned as the reason, so
// the skip reason is explainable in logs and in the admin view.
import type { AiPushInsight } from "./ai.ts";

export type SkipReason =
  | "model_declined"
  | "priority_too_low"
  | "duplicate_fingerprint"
  | "cooldown_active"
  | "topic_cooldown_active"
  | "quiet_hours"
  | "insufficient_data"
  | "empty_message";

export interface DecisionInput {
  insight: AiPushInsight;
  /** Stable hash of the message's meaning; see `fingerprintInsight`. */
  fingerprint: string;
  /** When the last push of any kind was delivered, if any. */
  lastNotifiedAt: string | null;
  /** Fingerprints already delivered, most recent first. */
  recentFingerprints: string[];
  /**
   * The most recent delivered push of a given topic, or null when that topic has
   * never been notified. The topic is carried alongside the timestamp on
   * purpose: a bare timestamp would make the per-topic rule block *every* topic
   * once any push went out, which is just a stricter copy of the global
   * cooldown and defeats the point of having two limits.
   */
  lastTopicNotified: { topic: string; at: string } | null;
  /** The user's summary `hasEnoughData`. */
  hasEnoughData: boolean;
  /** Whether the user is in a quiet period and should not be interrupted. */
  inQuietHours?: boolean;
  /**
   * Minutes east of UTC for the user's device, from
   * `app_settings.notifications.utc_offset_minutes`. Absent for a user who has
   * never opened the app since this was added, in which case quiet hours are
   * evaluated in UTC.
   */
  utcOffsetMinutes?: number | null;
}

export interface DecisionConfig {
  /** Minimum AI priority allowed to send. */
  minPriority: AiPushInsight["priority"];
  /** Hours between any two pushes. */
  minHoursBetweenPushes: number;
  /** Hours between two pushes on the same topic. */
  minHoursPerTopic: number;
  /** How many past fingerprints count as duplicates. */
  dedupeWindow: number;
  /** When true, drops everything outside a quiet-hours-free window. */
  respectQuietHours: boolean;
}

export const DEFAULT_DECISION_CONFIG: DecisionConfig = {
  minPriority: "normal",
  minHoursBetweenPushes: 20,
  minHoursPerTopic: 72,
  dedupeWindow: 10,
  respectQuietHours: true,
};

export type Decision =
  | { send: true }
  | { send: false; reason: SkipReason };

const HOUR = 60 * 60 * 1000;

const PRIORITY_RANK: Record<AiPushInsight["priority"], number> = {
  low: 0,
  normal: 1,
  high: 2,
};

function hoursBetween(from: string | null, to: number): number {
  if (!from) return Number.POSITIVE_INFINITY;
  const at = new Date(from).getTime();
  if (!Number.isFinite(at)) return Number.POSITIVE_INFINITY;
  return (to - at) / HOUR;
}

/**
 * The hour of day where the user actually is.
 *
 * Uses the device's UTC offset rather than an IANA zone name on purpose: the
 * offset is what the client can report without a platform channel, and it stays
 * correct for zones with a half-hour offset (Nepal is +5:45, which a whole-hour
 * offset cannot express) without either side needing a timezone database. It is
 * only as fresh as the client's last write, which is why the client refreshes it
 * on launch; a stale value shifts the quiet window by an hour at worst, and
 * only across a DST boundary.
 */
export function localHour(
  date: Date,
  utcOffsetMinutes?: number | null,
): number {
  if (
    typeof utcOffsetMinutes !== "number" || !Number.isFinite(utcOffsetMinutes)
  ) {
    // Unknown. UTC is the documented fallback: it keeps the window aligned with
    // the server's schedule rather than skipping quiet hours entirely.
    return date.getUTCHours();
  }
  // Shifting the instant and reading UTC is how the wrap past midnight is
  // handled for free.
  return new Date(date.getTime() + utcOffsetMinutes * 60_000).getUTCHours();
}

function isQuietHour(date: Date, utcOffsetMinutes?: number | null): boolean {
  // 22:00-08:00 where the user is, matching the reminder settings they already
  // have. The cron fires at a fixed UTC time, so without the offset a user in
  // Kathmandu would be handed a window shifted by 5h45m.
  const hour = localHour(date, utcOffsetMinutes);
  return hour >= 22 || hour < 8;
}

export function decide(
  input: DecisionInput,
  config: DecisionConfig = DEFAULT_DECISION_CONFIG,
  now: number = Date.now(),
): Decision {
  const { insight } = input;

  if (!insight.shouldNotify) return { send: false, reason: "model_declined" };
  if (!insight.message.trim()) return { send: false, reason: "empty_message" };

  if (PRIORITY_RANK[insight.priority] < PRIORITY_RANK[config.minPriority]) {
    return { send: false, reason: "priority_too_low" };
  }

  // A user with barely any history is not a good audience for a "you spent X
  // unusually" style push; the model can only be guessing at that point.
  if (!input.hasEnoughData) {
    return { send: false, reason: "insufficient_data" };
  }

  if (
    input.recentFingerprints.slice(0, config.dedupeWindow).includes(
      input.fingerprint,
    )
  ) {
    return { send: false, reason: "duplicate_fingerprint" };
  }

  if (
    config.respectQuietHours &&
    (input.inQuietHours ?? isQuietHour(new Date(now), input.utcOffsetMinutes))
  ) {
    return { send: false, reason: "quiet_hours" };
  }

  if (hoursBetween(input.lastNotifiedAt, now) < config.minHoursBetweenPushes) {
    return { send: false, reason: "cooldown_active" };
  }

  const lastInTopic = input.lastTopicNotified;
  if (
    lastInTopic?.topic === insight.topic &&
    hoursBetween(lastInTopic.at, now) < config.minHoursPerTopic
  ) {
    return { send: false, reason: "topic_cooldown_active" };
  }

  return { send: true };
}

/**
 * A stable id for "the same message".
 *
 * Amounts move every single day, so a literal hash would treat yesterday's
 * "NPR 13,325" and today's "NPR 13,924" as different messages and let the same
 * insight through on consecutive days. Numbers are therefore bucketed to one
 * significant figure, which keeps small day-to-day drift a duplicate while
 * still separating genuinely different magnitudes ("NPR 13,325" and
 * "NPR 81,400" must not dedupe to each other - that is a 6x jump and a different
 * insight entirely).
 *
 * The trade-off is deliberate and biased toward under-notifying: a real 50%
 * swing may be folded into an existing fingerprint and suppressed, because
 * missing one notification is far cheaper than sending a duplicate every day.
 */
export function fingerprintInsight(insight: AiPushInsight): string {
  return [
    insight.topic,
    insight.deepLink,
    bucketDigits(insight.title),
    bucketDigits(insight.message),
  ].join("|");
}

/** Collapses each number in [text] to one significant figure. */
function bucketDigits(text: string): string {
  return text.replace(/\d[\d,]*/g, (match) => {
    const value = Number(match.replace(/,/g, ""));
    if (!Number.isFinite(value) || value <= 0) return "#";
    // Small figures (a year, a count) carry meaning at their own scale.
    if (value < 1000) return String(value);
    const magnitude = Math.pow(10, Math.floor(Math.log10(value)));
    return String(Math.round(value / magnitude) * magnitude);
  });
}
