// Provider-agnostic AI call + STRICT response validation.
//
// The API key lives ONLY here, as a Supabase Edge Function secret. It is never
// bundled into the Flutter client.
import OpenAI from "npm:openai@4";
import {
  type AiInsight,
  CATEGORIES,
  clamp,
  type InsightTone,
  MAX_MESSAGE,
  parseJsonObject,
  pick,
  PRIORITIES,
  validateInsight,
} from "./insight_validation.ts";

export {
  type AiInsight,
  INSIGHT_KINDS,
  type InsightTone,
  MOODS,
  TONES,
  validateInsight,
} from "./insight_validation.ts";

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
  options: {
    allowedTone?: InsightTone;
    grounding?: unknown[];
    kind?: string;
  } = {},
): Promise<AiInsight> {
  const raw = await complete(systemPrompt, userPrompt, 400);
  return validateInsight(raw, promptVersion, options);
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

/** Canned lines, used when the model is unavailable or repeats itself. */
const FALLBACK_BUDDY: Record<string, Array<[string, string]>> = {
  morning: [
    ["Good morning! ☀️", "New day, fresh budget. Log your first spend and let's keep the flame bright 🔥"],
    ["Rise and shine! 🌅", "Hmmm… a great day to save a little money. You've got this 💪"],
    ["Good morning 🌞", "Coffee first, then let's keep today's spending light ☕"],
    ["Morning! 🔥", "I'm awake and warm. One small saving today and I'll glow all day ✨"],
    ["Good morning 🌤️", "Decide today's spending limit now, before the day decides it for you 🎯"],
    ["Up and at it! 🌄", "Yesterday is logged, today is a clean page. Let's write a good one 📒"],
  ],
  late_morning: [
    ["Quick check-in 👋", "Spent anything this morning? Log it now so nothing slips away 📝"],
    ["Day's just started 🌤️", "Pick one thing you won't buy today. That's your win 🏆"],
    ["Psst… 🔥", "Carrying water and a snack saves more than you'd think 💧"],
    ["Morning money tip 💡", "Check your budget once before lunch. Two taps, no surprises 📊"],
    ["Hello hello 👀", "Any tea, bus fare or snack so far? Tiny spends count too ☕"],
  ],
  midday: [
    ["Lunch time! 🍛", "Enjoy it, then log it. I like knowing what we ate 😋"],
    ["Midday nudge 🕛", "Half the day done. How's the wallet holding up? 👛"],
    ["Money tip 💡", "Before you buy, wait 10 minutes. If you still want it, go for it!"],
    ["Psst… 🔥", "Home lunch twice this week keeps me burning bright ✨"],
    ["Quick one 📝", "Log this morning's spends now, while you still remember them."],
  ],
  afternoon: [
    ["Afternoon slump? ☕", "A walk is free. That second coffee isn't. Just saying 😉"],
    ["Still here 🔥", "Small savings add up. Skip one extra today and I'll glow brighter ✨"],
    ["Tiny challenge 🎯", "No spending until dinner. Think you can do it? 💪"],
    ["Afternoon check 📊", "A quick look at this month's spending takes ten seconds 👀"],
    ["Fun fact 🪙", "A rupee saved daily is a whole day's spending by month end. Slow and steady 🐢"],
  ],
  evening: [
    ["Evening! 🌇", "Day's nearly done. Log what's left before it slips your mind 📝"],
    ["How was today? 🙂", "Add up today's spends. If it was light, be proud 🌟"],
    ["Dinner plans? 🍲", "Cooking tonight is a saving and a meal in one 🔥"],
    ["Wind-down tip 🌆", "Set tomorrow's spending limit tonight. Future you will thank you 🙏"],
    ["Almost there 🏁", "One last check of the budget, then the evening is yours 📊"],
  ],
  night: [
    ["Good night! 🌙", "Day's done. Quick look at today's spending, then rest well 😴"],
    ["Sweet dreams 🌙", "Thanks for tracking today. Tomorrow we save even more 💤"],
    ["Good night 🌟", "The flame is going to sleep. See you at sunrise! 😴"],
    ["Lights out 🕯️", "Whatever today cost, it's logged and done. Sleep easy 😌"],
    ["Night night 🌜", "I'm banking the embers for tomorrow. Rest well 💤"],
    ["Good night 😴", "One more day tracked. That habit is worth more than any one saving 🌟"],
  ],
};

/** Loose comparison, so a line that differs only in punctuation still counts. */
function sameLine(a: string, b: string): boolean {
  const norm = (t: string) => t.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
  return norm(a) === norm(b);
}

export interface BuddyOptions {
  /** For a daytime slot: late_morning, midday, afternoon or evening. */
  part?: string | null;
  /** Bodies sent to this user recently, newest first. */
  recent?: string[];
}

export function fallbackBuddyMessage(
  slot: BuddySlotKind,
  seed: number,
  options: BuddyOptions = {},
): BuddyMessage {
  const pool = slot === "day"
    ? FALLBACK_BUDDY[options.part ?? "afternoon"] ?? FALLBACK_BUDDY.afternoon
    : FALLBACK_BUDDY[slot];
  const recent = options.recent ?? [];
  const start = Math.abs(seed) % pool.length;
  // Walk on from the seeded line until one turns up that was not sent lately.
  for (let step = 0; step < pool.length; step++) {
    const [title, message] = pool[(start + step) % pool.length];
    if (!recent.some((line) => sameLine(line, message))) {
      return { title, message, source: "fallback" };
    }
  }
  const [title, message] = pool[start];
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
  options: BuddyOptions = {},
): Promise<BuddyMessage> {
  try {
    const raw = await complete(systemPrompt, userPrompt, 200);
    const parsed = parseJsonObject(raw);
    const message = clamp(parsed?.message, MAX_PUSH_MESSAGE);
    if (!message) return fallbackBuddyMessage(slot, seed, options);
    // The model was told what it sent lately; if it says it again anyway, a
    // canned line the user has not just seen is the better notification.
    if ((options.recent ?? []).some((line) => sameLine(line, message))) {
      return fallbackBuddyMessage(slot, seed, options);
    }
    const title = clamp(parsed?.title, MAX_PUSH_TITLE) ||
      fallbackBuddyMessage(slot, seed, options).title;
    return { title, message, source: "ai" };
  } catch (error) {
    console.error("buddy: model failed, using fallback", String(error));
    return fallbackBuddyMessage(slot, seed, options);
  }
}
