// @ts-nocheck
// Turns the bytes of a statement file into what the parsers read: the
// positioned text of a PDF's pages, or the rows of a spreadsheet. The only
// place the PDF and spreadsheet libraries are used.
import { cellText, type TextItem } from './statement_parse.ts';

export const MAX_PAGES = 80;
export const MAX_SHEET_ROWS = 20_000;

export type PdfText =
  | { pages: TextItem[][] }
  | { tooLong: number }
  | { locked: true };

export async function readPdfText(data: Uint8Array): Promise<PdfText> {
  // The legacy build runs on the main thread (fake worker), which is required
  // in Deno because there is no worker file to load.
  const pdfjs = await import('npm:pdfjs-dist@4.10.38/legacy/build/pdf.mjs');
  let doc;
  try {
    doc = await pdfjs.getDocument({ data }).promise;
  } catch (error) {
    // A statement the bank protected with a password cannot be opened here.
    if (error?.name === 'PasswordException') return { locked: true };
    throw error;
  }
  if (doc.numPages > MAX_PAGES) return { tooLong: doc.numPages };
  const pages: TextItem[][] = [];
  for (let pageNo = 1; pageNo <= doc.numPages; pageNo++) {
    const page = await doc.getPage(pageNo);
    const content = await page.getTextContent();
    // Some banks store their pages rotated, so raw text positions have x and
    // y swapped. The viewport transform gives positions as the reader sees
    // them, whatever the rotation.
    const view = page.getViewport({ scale: 1 }).transform;
    const items: TextItem[] = [];
    for (const item of content.items) {
      if (!item || typeof item.str !== 'string' || !item.transform) continue;
      const seen = pdfjs.Util.transform(view, item.transform);
      items.push({
        str: item.str.replace(/ /g, ' '),
        x: seen[4],
        y: seen[5],
        width: item.width ?? 0,
      });
    }
    pages.push(items);
  }
  return { pages };
}

export async function readSheetRows(data: Uint8Array): Promise<string[][]> {
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
