// The shape of an insight and the checks every model reply goes through.
//
// Kept apart from ai.ts so it has no dependency on the AI client: it is pure
// and is unit tested without a model or a network.
import { ungroundedNumbers } from "./grounding.ts";

export interface AiInsight {
  title: string;
  message: string;
  category: "spending" | "saving" | "budget" | "income" | "general";
  priority: "low" | "normal" | "high";
  action: string;
  /** The expression that goes with what is said. */
  mood: (typeof MOODS)[number];
  /** How playful the wording is. Never more than the caller allowed. */
  tone: InsightTone;
  /** The moment it was written for: morning, midday, weekly, ... */
  kind?: string;
  promptVersion: string;
}

export const TONES = ["normal", "playful", "roast"] as const;
export type InsightTone = (typeof TONES)[number];

/** The moments a suggestion can be written for. */
export const INSIGHT_KINDS = [
  "morning",
  "midday",
  "evening",
  "endOfDay",
  "weekly",
  "monthly",
] as const;

export const CATEGORIES = [
  "spending",
  "saving",
  "budget",
  "income",
  "general",
] as const;
export const PRIORITIES = ["low", "normal", "high"] as const;
// Every expression the app's mascot can show for a suggestion. `neutral` is
// what an older app version understands; the rest are read by 1.0.15 on.
export const MOODS = [
  "happy",
  "excited",
  "proud",
  "celebrating",
  "curious",
  "thinking",
  "surprised",
  "shocked",
  "playful",
  "teasing",
  "roasting",
  "worried",
  "sad",
  "sleepy",
  "neutral",
] as const;

export const MAX_TITLE = 60;
export const MAX_MESSAGE = 280;
export const MAX_ACTION = 80;

export function clamp(value: unknown, max: number, fallback = ""): string {
  if (typeof value !== "string") return fallback;
  const trimmed = value.trim().replace(/\s+/g, " ");
  return trimmed.length > max ? `${trimmed.slice(0, max - 1)}…` : trimmed;
}

export function pick<T extends readonly string[]>(
  value: unknown,
  allowed: T,
  fallback: T[number],
): T[number] {
  return typeof value === "string" &&
      (allowed as readonly string[]).includes(value)
    ? (value as T[number])
    : fallback;
}

export function parseJsonObject(content: string): Record<string, unknown> | null {
  const cleaned = content
    .trim()
    .replace(/^```(?:json)?/i, "")
    .replace(/```$/i, "")
    .trim();
  try {
    const parsed = JSON.parse(cleaned);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : null;
  } catch {
    // Fall back to the first {...} block if the model added prose.
    const match = cleaned.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
      const parsed = JSON.parse(match[0]);
      return parsed && typeof parsed === "object"
        ? (parsed as Record<string, unknown>)
        : null;
    } catch {
      return null;
    }
  }
}

/**
 * Turns the model's raw reply into a validated insight, or throws.
 *
 * Besides the shape, two things are enforced here rather than trusted to the
 * prompt:
 *   * the tone is never more playful than `allowedTone`;
 *   * every amount and percentage in the text is one that `grounding` (the
 *     summary and context the model was given) actually contains. A reply
 *     that quotes a figure from nowhere is rejected.
 */
export function validateInsight(
  raw: string,
  promptVersion: string,
  options: {
    allowedTone?: InsightTone;
    grounding?: unknown[];
    kind?: string;
  } = {},
): AiInsight {
  const parsed = parseJsonObject(raw);
  if (!parsed) {
    throw new Error("AI returned malformed JSON.");
  }

  const message = clamp(parsed.message, MAX_MESSAGE);
  if (!message) {
    throw new Error("AI returned an empty message.");
  }
  const title = clamp(parsed.title, MAX_TITLE, "Smart Insight");

  if (options.grounding) {
    const invented = ungroundedNumbers(`${title}. ${message}`, ...options.grounding);
    if (invented.length > 0) {
      throw new Error(
        `AI quoted a figure that is not in the user's data (${
          invented.slice(0, 3).join(", ")
        }).`,
      );
    }
  }

  const allowed = TONES.indexOf(options.allowedTone ?? "normal");
  const said = TONES.indexOf(pick(parsed.tone, TONES, "normal"));
  const tone = TONES[Math.min(said, allowed)];
  let mood = pick(parsed.mood, MOODS, "neutral");
  // The face must not be more pointed than the words were allowed to be.
  if (mood === "roasting" && tone !== "roast") mood = "teasing";
  if (mood === "teasing" && tone === "normal") mood = "curious";

  return {
    title,
    message,
    category: pick(parsed.category, CATEGORIES, "general"),
    priority: pick(parsed.priority, PRIORITIES, "low"),
    action: clamp(parsed.action ?? "", MAX_ACTION),
    mood,
    tone,
    ...(options.kind ? { kind: options.kind } : {}),
    promptVersion,
  };
}
