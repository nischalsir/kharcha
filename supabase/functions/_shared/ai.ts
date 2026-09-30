// Provider-agnostic AI call + STRICT response validation.
//
// The API key lives ONLY here, as a Supabase Edge Function secret. It is never
// bundled into the Flutter client.
import OpenAI from "npm:openai@4";

export interface AiInsight {
  title: string;
  message: string;
  category: "spending" | "saving" | "budget" | "income" | "general";
  priority: "low" | "normal" | "high";
  action: string;
  mood: "happy" | "neutral" | "sad" | "sleepy";
  promptVersion: string;
}

const CATEGORIES = [
  "spending",
  "saving",
  "budget",
  "income",
  "general",
] as const;
const PRIORITIES = ["low", "normal", "high"] as const;
const MOODS = ["happy", "neutral", "sad", "sleepy"] as const;

const MAX_TITLE = 60;
const MAX_MESSAGE = 280;
const MAX_ACTION = 80;

function client(): OpenAI {
  const apiKey = Deno.env.get("NVIDIA_API_KEY") ?? Deno.env.get("AI_API_KEY");
  if (!apiKey) {
    throw new Error("AI key is not configured on the server.");
  }
  return new OpenAI({
    apiKey,
    baseURL: Deno.env.get("AI_API_BASE_URL") ??
      "https://integrate.api.nvidia.com/v1",
    // Never let a stuck upstream connection hang the Edge Function: fail fast
    // so the app receives a 502 and falls back to its local insight.
    timeout: 30_000,
    maxRetries: 1,
  });
}

// The account's NVIDIA key is entitled to a subset of the catalogue. Ids that
// are listed but not entitled do NOT fail fast - the request is accepted and
// never returns, which looks exactly like a broken app. Every model below was
// verified to return a completion with the real insight prompt.
const DEFAULT_MODEL = "moonshotai/kimi-k3";

function model(): string {
  return Deno.env.get("AI_MODEL") ?? DEFAULT_MODEL;
}

function clamp(value: unknown, max: number, fallback = ""): string {
  if (typeof value !== "string") return fallback;
  const trimmed = value.trim().replace(/\s+/g, " ");
  return trimmed.length > max ? `${trimmed.slice(0, max - 1)}…` : trimmed;
}

function pick<T extends readonly string[]>(
  value: unknown,
  allowed: T,
  fallback: T[number],
): T[number] {
  return typeof value === "string" &&
      (allowed as readonly string[]).includes(value)
    ? (value as T[number])
    : fallback;
}

function parseJsonObject(content: string): Record<string, unknown> | null {
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

export interface AiProbe {
  keyConfigured: boolean;
  model: string;
  baseUrl: string;
  catalogStatus: number;
  catalogCount: number;
  catalogSample: string[];
  configuredModelListed: boolean;
  completionStatus: number;
  completionMs: number;
  completionPreview: string;
  completionError: string;
}

/**
 * Diagnostic probe used by the `?selftest` route.
 *
 * The upstream catalogue is the only way to tell "the key is wrong" apart from
 * "this model id does not exist" apart from "the model exists but the account
 * has no entitlement for it" - the last one is the nasty case, because NVIDIA
 * accepts the request and then never emits a first token.
 */
export async function probeAi(): Promise<AiProbe> {
  const apiKey = Deno.env.get("NVIDIA_API_KEY") ?? Deno.env.get("AI_API_KEY");
  const baseUrl = Deno.env.get("AI_API_BASE_URL") ??
    "https://integrate.api.nvidia.com/v1";
  const modelId = Deno.env.get("AI_MODEL") ?? DEFAULT_MODEL;

  const catalogSample: string[] = [];
  let catalogStatus = 0;
  try {
    const res = await fetch(`${baseUrl}/models`, {
      headers: apiKey ? { Authorization: `Bearer ${apiKey}` } : {},
      signal: AbortSignal.timeout(10_000),
    });
    catalogStatus = res.status;
    const json = (await res.json()) as { data?: { id?: string }[] };
    for (const entry of json.data ?? []) {
      if (entry?.id) catalogSample.push(entry.id);
    }
  } catch (error) {
    catalogSample.push(`<catalog error: ${String(error)}>`);
  }

  // A minimal, user-only completion: some models reject a system prompt, and we
  // want the shortest possible path to a first token.
  const started = Date.now();
  let completionStatus = 0;
  let preview = "";
  let error = "";
  try {
    const res = await fetch(`${baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(apiKey ? { Authorization: `Bearer ${apiKey}` } : {}),
      },
      body: JSON.stringify({
        model: modelId,
        messages: [{ role: "user", content: "Say OK." }],
        max_tokens: 16,
      }),
      signal: AbortSignal.timeout(20_000),
    });
    completionStatus = res.status;
    const text = await res.text();
    preview = text.slice(0, 400);
  } catch (caught) {
    error = caught instanceof Error ? caught.message : String(caught);
  }

  return {
    keyConfigured: Boolean(apiKey),
    model: modelId,
    baseUrl,
    catalogStatus,
    catalogCount: catalogSample.length,
    catalogSample: catalogSample.slice(0, 25),
    configuredModelListed: catalogSample.includes(modelId),
    completionStatus,
    completionMs: Date.now() - started,
    completionPreview: preview,
    completionError: error,
  };
}

async function complete(
  systemPrompt: string,
  userPrompt: string,
  maxTokens: number,
): Promise<string> {
  const response = await client().chat.completions.create({
    model: model(),
    messages: [
      { role: "system", content: systemPrompt },
      { role: "user", content: userPrompt },
    ],
    temperature: 0.6,
    top_p: 0.95,
    max_tokens: maxTokens,
  });
  return response.choices?.[0]?.message?.content ?? "";
}

/** Generates and validates a single insight. Throws on unrecoverable failure. */
export async function generateInsight(
  systemPrompt: string,
  userPrompt: string,
  promptVersion: string,
): Promise<AiInsight> {
  const raw = await complete(systemPrompt, userPrompt, 400);
  const parsed = parseJsonObject(raw);
  if (!parsed) {
    throw new Error("AI returned malformed JSON.");
  }

  const message = clamp(parsed.message, MAX_MESSAGE);
  if (!message) {
    throw new Error("AI returned an empty message.");
  }

  return {
    title: clamp(parsed.title, MAX_TITLE, "Smart Insight"),
    message,
    category: pick(parsed.category, CATEGORIES, "general"),
    priority: pick(parsed.priority, PRIORITIES, "low"),
    action: clamp(parsed.action ?? "", MAX_ACTION),
    mood: pick(parsed.mood, MOODS, "neutral"),
    promptVersion,
  };
}

/** Generates and validates a chat reply. Throws on unrecoverable failure. */
export async function generateChatReply(
  systemPrompt: string,
  userPrompt: string,
): Promise<string> {
  const raw = await complete(systemPrompt, userPrompt, 300);
  const parsed = parseJsonObject(raw);
  const reply = clamp(parsed?.reply, MAX_MESSAGE);
  if (!reply) {
    throw new Error("AI returned an empty reply.");
  }
  return reply;
}

// A push is shorter than a Home insight: it is read on a lock screen, often
// one-handed, and should not scroll.
const MAX_PUSH_TITLE = 40;
const MAX_PUSH_MESSAGE = 110;

export interface AiPushInsight {
  shouldNotify: boolean;
  title: string;
  message: string;
  /**
   * What the message is *about*, in the model's own vocabulary
   * (`spending` | `saving` | `budget` | `income` | `general`).
   *
   * Deliberately not the push category. The model's labels are a topic
   * taxonomy; the app's push categories (`ai_content`, `budget_warnings`, …)
   * are a delivery taxonomy that maps to Android channels and preference keys.
   * Conflating the two meant the model's "budget" resolved to no known
   * category, so every AI push silently fell back to the general channel
   * instead of the insights channel. The topic is still worth keeping: it is
   * what the per-topic cooldown and the "you were last told about…" hint in the
   * prompt reason over.
   */
  topic: AiInsight["category"];
  priority: AiInsight["priority"];
  /** Must be one of PUSH_DEEP_LINKS. */
  deepLink: string;
  promptVersion: string;
}

/**
 * The push category every AI insight is delivered as.
 *
 * AI content is not spread across the other categories on purpose: those carry
 * their own preference keys and their own channels, and borrowing one would let
 * a budget warning setting change where an AI insight appears, or route an
 * insight into the high-importance budget channel and make it interrupt.
 */
export const AI_PUSH_CATEGORY = "ai_content";

export class PushNotWorthSending extends Error {
  constructor(readonly reason: string) {
    super(reason);
    this.name = "PushNotWorthSending";
  }
}

/**
 * Generates and validates a push decision.
 *
 * Throws `PushNotWorthSending` when the model said no, and a plain Error when
 * the response could not be understood. The two are different: "no" is a
 * healthy, expected outcome of a well-tuned prompt, while a parse failure means
 * something is wrong and should be logged rather than silently skipped.
 */
export async function generatePushInsight(
  systemPrompt: string,
  userPrompt: string,
  promptVersion: string,
  allowedDeepLinks: readonly string[],
): Promise<AiPushInsight> {
  const raw = await complete(systemPrompt, userPrompt, 300);
  const parsed = parseJsonObject(raw);
  if (!parsed) {
    throw new Error("AI returned malformed JSON for a push decision.");
  }

  if (parsed.should_notify !== true) {
    throw new PushNotWorthSending("model declined to notify");
  }

  const title = clamp(parsed.title, MAX_PUSH_TITLE, "Insight");
  const message = clamp(parsed.message, MAX_PUSH_MESSAGE);
  if (!message) {
    throw new PushNotWorthSending("no message after clamping");
  }

  // An allowlisted route only: a model inventing a path must not be able to
  // send a user somewhere that does not exist.
  const deepLink = typeof parsed.deep_link === "string"
    ? parsed.deep_link.trim()
    : "";
  if (!allowedDeepLinks.includes(deepLink)) {
    throw new Error(
      `AI returned a deep link outside the allowlist: ${deepLink}`,
    );
  }

  return {
    shouldNotify: true,
    title,
    message,
    topic: pick(parsed.topic, CATEGORIES, "general"),
    priority: pick(parsed.priority, PRIORITIES, "normal"),
    deepLink,
    promptVersion,
  };
}

// ---------------------------------------------------------------------------
// Daily buddy: good morning / daytime nudge / good night from the flame.
// ---------------------------------------------------------------------------

export type BuddySlotKind = "morning" | "day" | "night";

export interface BuddyMessage {
  title: string;
  message: string;
  /** "ai" when the model wrote it, "fallback" for the canned lines. */
  source: "ai" | "fallback";
}

const FALLBACK_BUDDY: Record<BuddySlotKind, Array<[string, string]>> = {
  morning: [
    ["Good morning! ☀️", "New day, fresh budget. Log your first spend and let's keep the flame bright 🔥"],
    ["Rise and shine! 🌅", "Hmmm… a great day to save a little money. You've got this 💪"],
    ["Good morning 🌞", "Coffee first, then let's keep today's spending light ☕"],
  ],
  day: [
    ["Quick check-in 👋", "Spent anything today? Log it now so nothing slips away 📝"],
    ["Psst… 🔥", "Small savings add up. Skip one extra today and I'll glow brighter ✨"],
    ["Money tip 💡", "Before you buy, wait 10 minutes. If you still want it, go for it!"],
  ],
  night: [
    ["Good night! 🌙", "Day's done. Quick look at today's spending, then rest well 😴"],
    ["Sweet dreams 🌙", "Thanks for tracking today. Tomorrow we save even more 💤"],
    ["Good night 🌟", "The flame is going to sleep. See you at sunrise! 😴"],
  ],
};

export function fallbackBuddyMessage(
  slot: BuddySlotKind,
  seed: number,
): BuddyMessage {
  const options = FALLBACK_BUDDY[slot];
  const [title, message] = options[Math.abs(seed) % options.length];
  return { title, message, source: "fallback" };
}

/**
 * Asks the model for one short, friendly line. Never throws: any failure falls
 * back to a canned line, because a greeting that does not arrive at 06:00 is
 * worse than a generic one that does.
 */
export async function generateBuddyMessage(
  systemPrompt: string,
  userPrompt: string,
  slot: BuddySlotKind,
  seed: number,
): Promise<BuddyMessage> {
  try {
    const raw = await complete(systemPrompt, userPrompt, 200);
    const parsed = parseJsonObject(raw);
    const message = clamp(parsed?.message, MAX_PUSH_MESSAGE);
    if (!message) return fallbackBuddyMessage(slot, seed);
    const title = clamp(parsed?.title, MAX_PUSH_TITLE) ||
      fallbackBuddyMessage(slot, seed).title;
    return { title, message, source: "ai" };
  } catch (error) {
    console.error("buddy: model failed, using fallback", String(error));
    return fallbackBuddyMessage(slot, seed);
  }
}
