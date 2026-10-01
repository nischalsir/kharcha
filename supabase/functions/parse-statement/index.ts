// @ts-nocheck
// Kharcha statement importer.
//
// Pipeline: Flutter (file bytes, base64) -> this function -> text / cell
// extraction (statement_files.ts) -> the format that understands the file
// (statement_formats.ts) -> validated entries -> Flutter review screen.
//
// No API keys are involved. A file is recognised by its contents, never its
// name, and by its column headings, never by one bank's page layout. What
// cannot be read is reported back; nothing is saved here.
import { corsHeaders, json } from '../_shared/cors.ts';
import { getUser } from '../_shared/auth.ts';
import { detectKind } from '../_shared/statement_parse.ts';
import {
  MAX_PAGES,
  readPdfText,
  readSheetRows,
} from '../_shared/statement_files.ts';
import { readStatement } from '../_shared/statement_formats.ts';

// Platform JWT verification also accepts the public anon key, which ships in
// the app. Requiring a signed-in user, and bounding the work per request, keeps
// this CPU-heavy endpoint from being a free file parser for anyone.
const MAX_BASE64_LENGTH = 14_000_000; // ~10 MB file
const SOURCES = ['bank', 'esewa', 'khalti', 'other'];

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
  // `pdfBase64` is what app versions up to 1.0.3 send.
  const base64 = typeof body.fileBase64 === 'string'
    ? body.fileBase64
    : typeof body.pdfBase64 === 'string'
    ? body.pdfBase64
    : '';
  if (!base64) return json({ error: 'No file was sent.' }, 400);
  if (base64.length > MAX_BASE64_LENGTH) {
    return json({ error: 'File is too large (max 10 MB).' }, 413);
  }
  // What the user said the file is. Used only when the file does not say.
  const hint = SOURCES.includes(body.source) ? body.source : undefined;

  let data: Uint8Array;
  try {
    const bin = atob(base64);
    data = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) data[i] = bin.charCodeAt(i);
  } catch {
    return json({ error: 'Invalid base64 payload' }, 400);
  }

  const kind = detectKind(data);
  if (kind === 'unknown') {
    return json(
      {
        error: 'This is not a statement file Kharcha can read. Choose a PDF, ' +
          'Excel (.xls, .xlsx) or CSV statement.',
        reason: 'unsupported',
      },
      400,
    );
  }

  let parsed;
  try {
    if (kind === 'pdf') {
      const text = await readPdfText(data);
      if ('locked' in text) {
        return json({
          error: 'This PDF is protected with a password. Open it, save or ' +
            'print it as a new PDF without the password, and import that.',
          reason: 'locked',
        }, 422);
      }
      if ('tooLong' in text) {
        return json({
          error: `This statement has ${text.tooLong} pages (max ${MAX_PAGES}). ` +
            'Download a shorter period and import it in parts.',
          reason: 'too_long',
        }, 413);
      }
      const pieces = text.pages.reduce((sum, page) => sum + page.length, 0);
      if (pieces === 0) {
        // A scan or a photo: the page is a picture with no text to read.
        return json({
          error: 'This PDF is a picture of a statement, so there is no text ' +
            'to read. Download the statement from your bank\'s app or site ' +
            'as PDF, Excel or CSV instead of scanning it.',
          reason: 'scanned',
        }, 422);
      }
      parsed = readStatement({ kind: 'pdf', pages: text.pages, hint });
    } else {
      parsed = readStatement({
        kind: 'sheet',
        rows: await readSheetRows(data),
        hint,
      });
    }
  } catch (error) {
    // Logged, not returned: parser internals are no use to the app.
    console.error('parse-statement: could not read file', kind, String(error));
    return json({ error: 'Could not read this file.', reason: 'unreadable' }, 400);
  }

  // Bikram Sambat dates are converted by the app, with its calendar tables.
  // A version that has not said it can (1.0.14 and earlier) would read them
  // as AD dates half a century ahead, so for it those rows are reported.
  const acceptsBs = Array.isArray(body.accepts) && body.accepts.includes('bs');
  if (!acceptsBs) {
    const kept = [];
    for (const entry of parsed.entries) {
      if (entry.calendar === 'bs') {
        parsed.skipped.push({
          row: 0,
          reason: 'Bikram Sambat date',
          text: `${entry.occurred_at.slice(0, 10)} ${entry.description}`,
        });
      } else {
        kept.push(entry);
      }
    }
    parsed.entries = kept;
  }

  if (parsed.source === 'unknown' ||
    (parsed.entries.length === 0 && parsed.skipped.length === 0)) {
    return json({
      error: kind === 'pdf'
        ? 'No transaction table could be found in this PDF. If your bank ' +
          'offers it, download the statement as Excel or CSV and import ' +
          'that, or add the transactions by hand.'
        : 'No transaction table was found in this file. It needs a header ' +
          'row with a date and either debit/credit or amount columns.',
      reason: 'no_table',
      unreadPages: parsed.unreadPages ?? [],
      pageCount: parsed.pageCount ?? null,
    }, 422);
  }

  return json({
    entries: parsed.entries,
    skipped: parsed.skipped,
    source: parsed.source,
    count: parsed.entries.length,
    kind,
    format: parsed.format ?? null,
    provider: parsed.provider ?? null,
    layout: parsed.layout ?? null,
    unreadPages: parsed.unreadPages ?? [],
    pageCount: parsed.pageCount ?? null,
    balanceChecked: parsed.balanceChecked ?? false,
  });
});
