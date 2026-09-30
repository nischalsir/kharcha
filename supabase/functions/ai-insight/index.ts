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
import { generateChatReply, generateInsight, probeAi } from '../_shared/ai.ts';

const RATE_WINDOW_MS = 30_000; // per user+mode, best-effort (per isolate)
const MAX_QUESTION_LEN = 240;
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
  const context = body.context ?? {};

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
    const summary = await buildFinancialSummary(supabase);

    if (mode === 'chat') {
      const question = String(body.question ?? '').trim().slice(0, MAX_QUESTION_LEN);
      if (!question) return fail('Missing question', 400);
      const reply = await generateChatReply(
        CHAT_SYSTEM_PROMPT,
        buildChatUserPrompt(summary, context, question),
      );
      return json({ reply, promptVersion: PROMPT_VERSION });
    }

    const isBirthday =
      typeof context === 'object' &&
      context !== null &&
      (context as Record<string, unknown>).isBirthday === true;

    if (!summary.hasEnoughData) {
      return json({ insight: fallbackInsight(isBirthday ? 'birthday' : 'no_data') });
    }

    const insight = await generateInsight(
      INSIGHT_SYSTEM_PROMPT,
      buildInsightUserPrompt(summary, context),
      PROMPT_VERSION,
    );
    return json({ insight });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'AI request failed.';
    console.error('[ai-insight]', message);
    return fail(message, 502);
  }
});
