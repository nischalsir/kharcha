// @ts-nocheck
// Kharcha PDF statement importer.
//
// Pipeline: Flutter (PDF bytes, base64) -> this function -> pdf.js text
// extraction -> row parser -> validated entries -> Flutter review screen.
//
// No API keys are involved. The parser is written for the common Nepali bank
// "Electronic Account Statement" layout:
//   YYYY-MM-DD HH:MM:SS  Description  Withdraw  Deposit  Balance  S.N
import { corsHeaders, json } from '../_shared/cors.ts';
import { getUser } from '../_shared/auth.ts';

// Platform JWT verification also accepts the public anon key, which ships in
// the app. Requiring a signed-in user, and bounding the work per request, keeps
// this CPU-heavy endpoint from being a free PDF parser for anyone.
const MAX_BASE64_LENGTH = 14_000_000; // ~10 MB PDF
const MAX_PAGES = 60;

// The legacy build runs on the main thread (fake worker), which is required in
// Deno because there is no worker file to load.
const pdfjs = await import('npm:pdfjs-dist@4.10.38/legacy/build/pdf.mjs');

const rowRe = /^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+(.+)$/;
// Withdraw row:  "100.00 - 138.211"  (amount immediately before " - ").
const withdrawRe = /(\d[\d,]*\.\d{2})\s+-\s+\d/;
// Deposit row:   "- 5,000.00 5,013.216" (amount immediately after "- ").
const depositRe = /-\s+(\d[\d,]*\.\d{2})/;

function parseAmount(raw: string): number {
  return parseFloat(raw.replace(/,/g, ''));
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  if (!(await getUser(req))) return json({ error: 'Not authenticated' }, 401);

  let body: Record<string, unknown> = {};
  try {
    body = (await req.json()) as Record<string, unknown>;
  } catch {
    return json({ error: 'Invalid JSON body' }, 400);
  }
  const base64 = typeof body.pdfBase64 === 'string' ? body.pdfBase64 : '';
  if (!base64) return json({ error: 'Missing pdfBase64' }, 400);
  if (base64.length > MAX_BASE64_LENGTH) {
    return json({ error: 'PDF is too large (max 10 MB).' }, 413);
  }

  let data: Uint8Array;
  try {
    const bin = atob(base64);
    data = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) data[i] = bin.charCodeAt(i);
  } catch {
    return json({ error: 'Invalid base64 payload' }, 400);
  }

  let text = '';
  try {
    const doc = await pdfjs.getDocument({ data }).promise;
    if (doc.numPages > MAX_PAGES) {
      return json({ error: `Statement has too many pages (max ${MAX_PAGES}).` }, 413);
    }
    for (let pageNo = 1; pageNo <= doc.numPages; pageNo++) {
      const page = await doc.getPage(pageNo);
      const content = await page.getTextContent();
      for (const item of content.items) {
        if (item && typeof item.str === 'string') {
          text += item.str;
          text += item.hasEOL ? '\n' : ' ';
        }
      }
      text += '\n';
    }
  } catch (error) {
    // Logged, not returned: parser internals are no use to the app.
    console.error('parse-statement: could not read PDF', String(error));
    return json({ error: 'Could not read this PDF.' }, 400);
  }

  const entries: Array<Record<string, unknown>> = [];
  for (const rawLine of text.split('\n')) {
    const line = rawLine.replace(/\u00a0/g, ' ').trim();
    const row = line.match(rowRe);
    if (!row) continue;

    const stamp = row[1];
    const rest = row[2];

    let amount: number | null = null;
    let type: 'income' | 'expense' | null = null;
    let matchIndex = -1;

    const withdraw = rest.match(withdrawRe);
    if (withdraw && withdraw.index !== undefined) {
      amount = parseAmount(withdraw[1]);
      type = 'expense';
      matchIndex = withdraw.index;
    } else {
      const deposit = rest.match(depositRe);
      if (deposit && deposit.index !== undefined) {
        amount = parseAmount(deposit[1]);
        type = 'income';
        matchIndex = deposit.index;
      }
    }
    if (amount === null || type === null || !(amount > 0)) continue;

    const description = rest
      .substring(0, matchIndex)
      .replace(/[\s,\-:]+$/, '')
      .replace(/\s+/g, ' ')
      .trim();
    if (!description) continue;

    entries.push({
      occurred_at: stamp,
      description,
      amount: Math.round(amount * 100) / 100,
      type,
    });
  }

  return json({ entries, count: entries.length });
});
