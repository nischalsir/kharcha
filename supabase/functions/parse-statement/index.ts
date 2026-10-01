// @ts-nocheck
// Kharcha statement importer.
//
// Pipeline: Flutter (file bytes, base64) -> this function -> text / cell
// extraction -> row parser -> validated entries -> Flutter review screen.
//
// No API keys are involved. Two files are understood, told apart by their
// contents rather than their names:
//   * the bank "Electronic Account Statement" PDF
//   * the eSewa "Statement Report" spreadsheet (.xls / .xlsx)
import { corsHeaders, json } from '../_shared/cors.ts';
import { getUser } from '../_shared/auth.ts';
import {
  cellText,
  detectKind,
  parseBankPages,
  parseSheet,
} from '../_shared/statement_parse.ts';

// Platform JWT verification also accepts the public anon key, which ships in
// the app. Requiring a signed-in user, and bounding the work per request, keeps
// this CPU-heavy endpoint from being a free file parser for anyone.
const MAX_BASE64_LENGTH = 14_000_000; // ~10 MB file
const MAX_PAGES = 60;
const MAX_SHEET_ROWS = 20_000;

async function readPdf(data: Uint8Array) {
  // The legacy build runs on the main thread (fake worker), which is required
  // in Deno because there is no worker file to load.
  const pdfjs = await import('npm:pdfjs-dist@4.10.38/legacy/build/pdf.mjs');
  const doc = await pdfjs.getDocument({ data }).promise;
  if (doc.numPages > MAX_PAGES) return null;
  const pages = [];
  for (let pageNo = 1; pageNo <= doc.numPages; pageNo++) {
    const page = await doc.getPage(pageNo);
    const content = await page.getTextContent();
    // The bank's pages are stored rotated, so raw text positions have x and y
    // swapped. The viewport transform gives positions as the reader sees them.
    const view = page.getViewport({ scale: 1 }).transform;
    const items = [];
    for (const item of content.items) {
      if (!item || typeof item.str !== 'string' || !item.transform) continue;
      const seen = pdfjs.Util.transform(view, item.transform);
      items.push({
        str: item.str.replace(/\u00a0/g, ' '),
        x: seen[4],
        y: seen[5],
        width: item.width ?? 0,
      });
    }
    pages.push(items);
  }
  return pages;
}

async function readSheet(data: Uint8Array) {
  const xlsx = await import('npm:xlsx@0.18.5');
  // `raw` keeps CSV text as typed, and `cellDates` hands real date cells over
  // as dates. Otherwise the library reformats every date as US m/d/yy, which
  // silently swaps day and month for everyone else.
  const book = xlsx.read(data, {
    type: 'array',
    sheetRows: MAX_SHEET_ROWS,
    raw: true,
    cellDates: true,
  });
  const sheet = book.Sheets[book.SheetNames[0]];
  if (!sheet) return [];
  const rows = xlsx.utils.sheet_to_json(sheet, {
    header: 1,
    raw: true,
    defval: '',
  });
  return rows.map((row) => (row as unknown[]).map(cellText));
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
      { error: 'Choose a statement as PDF, Excel (.xls, .xlsx) or CSV.' },
      400,
    );
  }

  let entries = [];
  let skipped = [];
  let source = 'bank';
  try {
    if (kind === 'pdf') {
      const pages = await readPdf(data);
      if (pages === null) {
        return json(
          { error: `Statement has too many pages (max ${MAX_PAGES}).` },
          413,
        );
      }
      entries = parseBankPages(pages);
      if (entries.length === 0) {
        // Text could not be laid out into the statement's columns. Saying so
        // is better than importing rows that might have the wrong amounts.
        return json({
          error:
            'This PDF could not be read reliably. Download the statement as ' +
            'Excel or CSV from your bank instead and import that.',
        }, 422);
      }
    } else {
      const parsed = parseSheet(await readSheet(data));
      entries = parsed.entries;
      skipped = parsed.skipped;
      source = parsed.source;
      if (source === 'unknown') {
        return json({
          error:
            'No transaction table was found in this file. It needs a header ' +
            'row with a date and either debit/credit or amount columns.',
        }, 422);
      }
    }
  } catch (error) {
    // Logged, not returned: parser internals are no use to the app.
    console.error('parse-statement: could not read file', kind, String(error));
    return json({ error: 'Could not read this file.' }, 400);
  }

  return json({ entries, skipped, source, count: entries.length, kind });
});
