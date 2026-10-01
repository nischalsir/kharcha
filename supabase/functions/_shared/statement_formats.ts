// Which reader a statement file goes to.
//
// A file is turned into a `StatementDocument` (the positioned text of a PDF,
// or the rows of a spreadsheet) and offered to each format in turn. The first
// one that reads transactions out of it wins. Supporting another bank or
// wallet whose layout none of these can read means adding one entry to
// `STATEMENT_FORMATS`; nothing else changes.

import {
  parseBankPages,
  type ParsedStatement,
  parseSheet,
  type StatementSourceId,
  type TextItem,
} from './statement_parse.ts';
import { parseStatementPdf } from './statement_pdf.ts';

export interface StatementDocument {
  kind: 'pdf' | 'sheet';
  /** The text of each PDF page, positioned as the reader sees it. */
  pages?: TextItem[][];
  /** The rows of the first sheet, as cell text. */
  rows?: string[][];
  /** The source the user picked, used when the file does not say. */
  hint?: StatementSourceId;
}

export interface StatementFormat {
  id: string;
  kind: 'pdf' | 'sheet';
  /** Returns null when this is not a file the format understands. */
  read(doc: StatementDocument): ParsedStatement | null;
}

// Names as they are printed on statements. Longer names first, so that
// "Global IME Bank" is not reported as "IME".
const PROVIDERS: [RegExp, string, StatementSourceId][] = [
  [/\besewa\b/i, 'eSewa', 'esewa'],
  [/\bkhalti\b/i, 'Khalti', 'khalti'],
  [/\bime ?pay\b/i, 'IME Pay', 'other'],
  [/\bconnect ?ips\b/i, 'connectIPS', 'other'],
  [/global ime bank/i, 'Global IME Bank', 'bank'],
  [/nabil bank/i, 'Nabil Bank', 'bank'],
  [/nic asia/i, 'NIC Asia Bank', 'bank'],
  [/nepal investment mega|\bnimb\b/i, 'Nepal Investment Mega Bank', 'bank'],
  [/himalayan bank/i, 'Himalayan Bank', 'bank'],
  [/everest bank/i, 'Everest Bank', 'bank'],
  [/standard chartered/i, 'Standard Chartered Bank Nepal', 'bank'],
  [/nepal sbi/i, 'Nepal SBI Bank', 'bank'],
  [/rastriya banijya/i, 'Rastriya Banijya Bank', 'bank'],
  [/agricultur(e|al) development bank/i, 'Agricultural Development Bank', 'bank'],
  [/nepal bank (limited|ltd)/i, 'Nepal Bank', 'bank'],
  [/kumari bank/i, 'Kumari Bank', 'bank'],
  [/laxmi sunrise/i, 'Laxmi Sunrise Bank', 'bank'],
  [/prabhu bank/i, 'Prabhu Bank', 'bank'],
  [/siddhartha bank/i, 'Siddhartha Bank', 'bank'],
  [/sanima bank/i, 'Sanima Bank', 'bank'],
  [/machhapuchchhre/i, 'Machhapuchchhre Bank', 'bank'],
  [/citizens bank/i, 'Citizens Bank International', 'bank'],
  [/prime commercial/i, 'Prime Commercial Bank', 'bank'],
  [/nmb bank/i, 'NMB Bank', 'bank'],
];

/** The bank or wallet a statement's own heading names, if it names one. */
export function detectProvider(
  heading: string,
): { name: string; source: StatementSourceId } | null {
  for (const [pattern, name, source] of PROVIDERS) {
    if (pattern.test(heading)) return { name, source };
  }
  return null;
}

/** The text at the top of the first page, before any transaction. */
function pdfHeading(pages: TextItem[][]): string {
  const first = pages[0] ?? [];
  const top = [...first].sort((a, b) => a.y - b.y).slice(0, 20);
  return top.map((item) => item.str).join(' ');
}

export const STATEMENT_FORMATS: StatementFormat[] = [
  {
    // The "Electronic Account Statement" layout: full timestamps under the
    // exact headings Description / Withdraw / Deposit / Balance.
    id: 'bank-pdf-classic',
    kind: 'pdf',
    read(doc) {
      const entries = parseBankPages(doc.pages ?? []);
      if (entries.length === 0) return null;
      return { entries, skipped: [], source: 'bank' };
    },
  },
  {
    // Any other statement PDF, read by its column headings.
    id: 'pdf-table',
    kind: 'pdf',
    read(doc) {
      const pages = doc.pages ?? [];
      const parsed = parseStatementPdf(pages);
      if (parsed.format === 'none') return null;
      const named = detectProvider(parsed.preamble || pdfHeading(pages));
      const source = named?.source ?? doc.hint ?? 'bank';
      const method = source === 'esewa' || source === 'khalti'
        ? source
        : undefined;
      return {
        entries: method
          ? parsed.entries.map((entry) => ({ ...entry, method }))
          : parsed.entries,
        skipped: parsed.skipped,
        source,
        provider: named?.name,
        format: parsed.format === 'lines' ? 'pdf-lines' : 'pdf-table',
        layout: parsed.layout,
        unreadPages: parsed.unreadPages,
        balanceChecked: parsed.balanceChecked,
      };
    },
  },
  {
    // eSewa's own report, and any bank or wallet spreadsheet with named
    // columns.
    id: 'sheet',
    kind: 'sheet',
    read(doc) {
      const parsed = parseSheet(doc.rows ?? [], doc.hint);
      return parsed.source === 'unknown' ? null : parsed;
    },
  },
];

/**
 * Reads a statement with the first format that understands it. When none
 * does, the result has no entries and `source: 'unknown'`.
 */
export function readStatement(doc: StatementDocument): ParsedStatement {
  let partial: ParsedStatement | null = null;
  for (const format of STATEMENT_FORMATS) {
    if (format.kind !== doc.kind) continue;
    const parsed = format.read(doc);
    if (!parsed) continue;
    const result: ParsedStatement = {
      ...parsed,
      format: parsed.format ?? format.id,
    };
    if (doc.kind === 'pdf') {
      result.pageCount = doc.pages?.length ?? 0;
      if (format.id === 'bank-pdf-classic') {
        result.provider = detectProvider(pdfHeading(doc.pages ?? []))?.name;
      }
    }
    if (result.entries.length > 0) return result;
    // Understood the layout but could read no row: keep what it reported.
    partial ??= result;
  }
  return partial ?? {
    entries: [],
    skipped: [],
    source: 'unknown',
    pageCount: doc.pages?.length,
  };
}
