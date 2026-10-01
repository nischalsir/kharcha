// Kharcha AI Edge Function.
//
// Pipeline:  Flutter  ->  this function (auth + secure aggregation)  ->
//            NVIDIA/NIM model  ->  validation  ->  structured JSON  ->  Flutter
//
// The model never sees the database directly: only the compact summary built by
// `buildFinancialSummary`, scoped to the caller's JWT via RLS. The API key is a
// server secret (NVIDIA_API_KEY) and is never returned to the client.
//
// The same aggregation + prompt + validation modules are reused verbatim by the
// future FCM notification worker, so push notifications need no AI rewrite.
import { createClient } from 'npm:@supabase/supabase-js@2';
import { corsHeaders, fail, json } from '../_shared/cors.ts';
import { buildFinancialSummary } from '../_shared/summary.ts';
import {
  buildChatUserPrompt,
  buildInsightUserPrompt,
  CHAT_SYSTEM_PROMPT,
  INSIGHT_SYSTEM_PROMPT,
  PROMPT_VERSION,
} from '../_shared/prompt.ts';
import {
  generateChatReply,
  generateInsight,
  INSIGHT_KINDS,
  type InsightTone,
  probeAi,
  TONES,
} from '../_shared/ai.ts';

const RATE_WINDOW_MS = 30_000; // per user+mode, best-effort (per isolate)
const MAX_QUESTION_LEN = 240;

/**
 * What the app may say about the request. Everything is checked: the context
 * is sent by a client, and it ends up in a prompt.
 */
function readContext(raw: unknown) {
  const input = raw && typeof raw === 'object'
    ? raw as Record<string, unknown>
    : {};
  const kind = INSIGHT_KINDS.includes(input.kind as never)
    ? input.kind as string
    : null;
  const tone: InsightTone = TONES.includes(input.tone as never)
    ? input.tone as InsightTone
    : 'normal';
  // Nepal's offset unless the app says otherwise; clamped to real time zones.
  const offset = typeof input.utcOffsetMinutes === 'number' &&
      Number.isFinite(input.utcOffsetMinutes)
    ? Math.max(-720, Math.min(840, Math.round(input.utcOffsetMinutes)))
    : 345;
  const avoid = Array.isArray(input.avoid)
    ? input.avoid
      .filter((item) => typeof item === 'string')
      .slice(0, 5)
      .map((item) => (item as string).slice(0, 80))
    : [];
  const name = typeof input.name === 'string'
    ? input.name.trim().split(/\s+/)[0].slice(0, 40)
    : null;
  return {
    kind,
    tone,
    offset,
    // Only these reach the model.
    forModel: {
      kind: kind ?? 'general',
      tone,
      avoid,
      ...(name ? { first_name: name } : {}),
      ...(typeof input.hour === 'number' ? { hour: input.hour } : {}),
      ...(input.isBirthday === true ? { isBirthday: true } : {}),
      ...(typeof input.weather === 'string'
        ? { weather: input.weather.slice(0, 40) }
        : {}),
    },
  };
}
const recent = new Map<string, number>();

function rateLimited(key: string): boolean {
  const now = Date.now();
  const last = recent.get(key) ?? 0;
  if (now - last < RATE_WINDOW_MS) return true;
  recent.set(key, now);
  return false;
}

function fallbackInsight(reason: 'no_data' | 'birthday') {
  if (reason === 'birthday') {
    return {
      title: 'Happy Birthday 🎉',
      message:
        'Wishing you a wonderful birthday! Treat yourself today — you have earned it.',
      category: 'general',
      priority: 'normal',
      action: 'Enjoy your day',
      mood: 'happy',
      tone: 'playful',
      promptVersion: PROMPT_VERSION,
    };
  }
  return {
    title: 'Smart Tip',
    message:
      'Keep tracking your expenses to unlock personalised insights.',
    category: 'general',
    priority: 'low',
    action: '',
    mood: 'neutral',
    tone: 'normal',
    promptVersion: PROMPT_VERSION,
  };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return fail('Method not allowed', 405);
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return fail('Missing bearer token', 401);

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false },
  });

  const { data: userData, error: userError } = await supabase.auth.getUser(token);
  if (userError || !userData.user) return fail('Not authenticated', 401);
  const userId = userData.user.id;

  let body: Record<string, unknown> = {};
  try {
    body = (await req.json()) as Record<string, unknown>;
  } catch {
    return fail('Invalid JSON body', 400);
  }

  const modeRaw = String(body.mode ?? '');
  const context = readContext(body.context);

  // ?selftest (or { "mode": "selftest" }) reports the AI configuration without
  // running a completion, so the key/model can be checked from the app.
  if (modeRaw === 'selftest' || new URL(req.url).searchParams.has('selftest')) {
    return json({ selftest: await probeAi() });
  }

  const mode = modeRaw === 'chat' ? 'chat' : 'insight';

  if (rateLimited(`${userId}:${mode}`)) {
    return fail('Too many requests. Please wait a moment.', 429);
  }

  try {
    // Every figure the model sees is worked out here, from the caller's own
    // rows (RLS), in the caller's own calendar days.
    const summary = await buildFinancialSummary(supabase, {
      utcOffsetMinutes: context.offset,
    });

    if (mode === 'chat') {
      const question = String(body.question ?? '').trim().slice(0, MAX_QUESTION_LEN);
      if (!question) return fail('Missing question', 400);
      const reply = await generateChatReply(
        CHAT_SYSTEM_PROMPT,
        buildChatUserPrompt(summary, context.forModel, question),
      );
      return json({ reply, promptVersion: PROMPT_VERSION });
    }

    const isBirthday = context.forModel.isBirthday === true;

    if (!summary.hasEnoughData) {
      return json({ insight: fallbackInsight(isBirthday ? 'birthday' : 'no_data') });
    }

    const insight = await generateInsight(
      INSIGHT_SYSTEM_PROMPT,
      buildInsightUserPrompt(summary, context.forModel),
      PROMPT_VERSION,
      {
        allowedTone: context.tone,
        // A figure the model writes must be one of these, or the reply is
        // refused and the app keeps the suggestion it wrote itself.
        grounding: [summary, context.forModel],
        kind: context.kind ?? undefined,
      },
    );
    return json({ insight });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'AI request failed.';
    console.error('[ai-insight]', message);
    return fail(message, 502);
  }
});
