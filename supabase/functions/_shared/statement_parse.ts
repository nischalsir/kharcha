// Pure row parsers for the statement importer. No I/O and no library imports,
// so they can be unit tested without a PDF or spreadsheet reader.
//
// This file holds the shared types and helpers, and the readers for:
//   * the bank "Electronic Account Statement" PDF
//       S.N | Transaction Date | Description | Withdraw | Deposit | Balance
//   * the eSewa "Statement Report" spreadsheet
//       Reference Code | Date Time | Description | Dr. | Cr. | Status | ...
//   * any other bank or wallet spreadsheet, read by its column names
// PDFs of other layouts are read by statement_pdf.ts, and statement_formats.ts
// decides which reader a file goes to.

export interface StatementEntry {
  occurred_at: string;
  description: string;
  amount: number;
  type: 'income' | 'expense';
  /** Set when the file itself says which wallet it is, e.g. `esewa`. */
  method?: string;
  /** The statement's own reference for the row, when it has one. */
  ref?: string;
  /**
   * `bs` when `occurred_at` is a Bikram Sambat date exactly as printed. The
   * app converts it with its own calendar tables.
   */
  calendar?: 'bs';
  /** The balance the statement prints after this row. */
  balance?: number;
  /** Set when the row should be looked at before it is imported. */
  check?: string;
}

/** A row that looked like a transaction but could not be read safely. */
export interface SkippedRow {
  /** 1-based row in the sheet, or 0 when the source has no row numbers. */
  row: number;
  /** 1-based page of a PDF the row was on. */
  page?: number;
  /** Why it was left out, in words the user can act on. */
  reason: string;
  /** What the row said, so the user can find it in their statement. */
  text: string;
}

export interface ParsedStatement {
  entries: StatementEntry[];
  skipped: SkippedRow[];
  /** Where the file says it is from; `unknown` when no layout was found. */
  source: StatementSourceId | 'unknown';
  /** Which reader understood the file. */
  format?: string;
  /** The bank or wallet named on the statement, when it names one. */
  provider?: string;
  /** The table's columns as found, for a PDF. */
  layout?: string | null;
  /** 1-based PDF pages that had text but no transaction that could be read. */
  unreadPages?: number[];
  pageCount?: number;
  /** True when amounts were confirmed against the statement's balances. */
  balanceChecked?: boolean;
}

export type StatementSourceId = 'bank' | 'esewa' | 'khalti' | 'other';

/**
 * One piece of text on a PDF page, with where it appears to the reader:
 * `x` from the left edge and `y` down from the top, after page rotation.
 */
export interface TextItem {
  str: string;
  x: number;
  y: number;
  width: number;
}

export type FileKind = 'pdf' | 'sheet' | 'unknown';

/** Identifies a file by its leading bytes rather than by its name. */
export function detectKind(bytes: Uint8Array): FileKind {
  const at = (i: number) => bytes[i] ?? -1;
  // %PDF
  if (at(0) === 0x25 && at(1) === 0x50 && at(2) === 0x44 && at(3) === 0x46) {
    return 'pdf';
  }
  // OLE compound file: legacy .xls
  if (at(0) === 0xd0 && at(1) === 0xcf && at(2) === 0x11 && at(3) === 0xe0) {
    return 'sheet';
  }
  // Zip: .xlsx
  if (at(0) === 0x50 && at(1) === 0x4b && at(2) === 0x03 && at(3) === 0x04) {
    return 'sheet';
  }
  // CSV has no signature: it is plain text with separators and line breaks.
  if (looksLikeCsv(bytes)) return 'sheet';
  return 'unknown';
}

function looksLikeCsv(bytes: Uint8Array): boolean {
  const sample = bytes.subarray(0, Math.min(bytes.length, 4096));
  if (sample.length < 8) return false;
  let separators = 0;
  let lines = 0;
  for (const byte of sample) {
    // A NUL or other control byte means a binary file, not text.
    if (byte === 0 || (byte < 0x09) || (byte > 0x0d && byte < 0x20)) {
      return false;
    }
    if (byte === 0x2c || byte === 0x3b || byte === 0x09) separators++;
    if (byte === 0x0a) lines++;
  }
  return lines >= 1 && separators >= 2;
}

const stampRe = /^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})/;
const amountRe = /^\d[\d,]*(\.\d+)?$/;

function toAmount(raw: string): number {
  const text = raw.trim();
  if (!amountRe.test(text)) return 0;
  const value = parseFloat(text.replace(/,/g, ''));
  return Number.isFinite(value) ? Math.round(value * 100) / 100 : 0;
}

function tidy(description: string): string {
  return description.replace(/\s+/g, ' ').replace(/[\s,\-:]+$/, '').trim();
}

const bankColumns = ['Description', 'Withdraw', 'Deposit', 'Balance'] as const;
type BankColumn = (typeof bankColumns)[number];

/**
 * Reads the bank statement PDF.
 *
 * The PDF draws every cell separately, so the text arrives as loose items
 * rather than lines. Items are regrouped into rows by their height on the
 * page, and each one is assigned to the column whose heading it sits under.
 * That is what tells a withdrawal from a deposit: both are bare numbers.
 */
export function parseBankPages(pages: TextItem[][]): StatementEntry[] {
  const entries: StatementEntry[] = [];
  // Column centres, taken from the heading row and kept across pages in case a
  // continuation page omits it.
  let centres: Record<BankColumn, number> | null = null;

  for (const items of pages) {
    const rows = new Map<number, TextItem[]>();
    for (const item of items) {
      if (!item.str.trim()) continue;
      // Cells of one row share a baseline to within a fraction of a point.
      const key = Math.round(item.y / 3);
      const row = rows.get(key);
      if (row) row.push(item);
      else rows.set(key, [item]);
    }

    // Top of the page first, so the heading is seen before its rows.
    const ordered = [...rows.entries()].sort((a, b) => a[0] - b[0]);
    for (const [, row] of ordered) {
      const heading = readHeading(row);
      if (heading) {
        centres = heading;
        continue;
      }
      if (!centres) continue;

      row.sort((a, b) => a.x - b.x);
      const stampItem = row.find((item) => stampRe.test(item.str.trim()));
      if (!stampItem) continue;
      const stamp = stampItem.str.trim().match(stampRe)!;

      const cells: Record<BankColumn, string[]> = {
        Description: [],
        Withdraw: [],
        Deposit: [],
        Balance: [],
      };
      for (const item of row) {
        if (item === stampItem) continue;
        // The serial number sits left of the date.
        if (item.x < stampItem.x) continue;
        cells[nearest(centres, item)].push(item.str.trim());
      }

      const description = tidy(cells.Description.join(' '));
      if (!description) continue;
      const occurredAt = `${stamp[1]} ${stamp[2]}`;
      const withdraw = toAmount(cells.Withdraw.join(''));
      const deposit = toAmount(cells.Deposit.join(''));
      if (withdraw > 0) {
        entries.push({
          occurred_at: occurredAt,
          description,
          amount: withdraw,
          type: 'expense',
        });
      }
      if (deposit > 0) {
        entries.push({
          occurred_at: occurredAt,
          description,
          amount: deposit,
          type: 'income',
        });
      }
    }
  }
  return entries;
}

function centre(item: TextItem): number {
  return item.x + item.width / 2;
}

function readHeading(row: TextItem[]): Record<BankColumn, number> | null {
  const found: Partial<Record<BankColumn, number>> = {};
  for (const item of row) {
    const label = item.str.trim() as BankColumn;
    if (bankColumns.includes(label)) found[label] = centre(item);
  }
  return bankColumns.every((name) => found[name] !== undefined)
    ? (found as Record<BankColumn, number>)
    : null;
}

function nearest(
  centres: Record<BankColumn, number>,
  item: TextItem,
): BankColumn {
  const x = centre(item);
  let best: BankColumn = 'Description';
  for (const name of bankColumns) {
    if (Math.abs(centres[name] - x) < Math.abs(centres[best] - x)) best = name;
  }
  return best;
}

/**
 * Reads the eSewa statement spreadsheet, given as rows of cell text.
 *
 * Dr. is money leaving the wallet and Cr. is money arriving. Rows that did not
 * complete moved no money and are left out, as are the totals under the table.
 */
export function parseEsewaRows(
  rows: unknown[][],
  skipped: SkippedRow[] = [],
): StatementEntry[] {
  const text = (value: unknown) => (value == null ? '' : String(value).trim());

  let headerIndex = -1;
  let columns: Record<string, number> = {};
  for (let i = 0; i < rows.length; i++) {
    const labels = (rows[i] ?? []).map((cell) => text(cell).toLowerCase());
    const date = labels.indexOf('date time');
    const dr = labels.indexOf('dr.');
    const cr = labels.indexOf('cr.');
    if (date < 0 || dr < 0 || cr < 0) continue;
    headerIndex = i;
    columns = {
      date,
      dr,
      cr,
      description: labels.indexOf('description'),
      status: labels.indexOf('status'),
      ref: labels.indexOf('reference code'),
    };
    break;
  }
  if (headerIndex < 0 || columns.description < 0) return [];

  const entries: StatementEntry[] = [];
  for (let i = headerIndex + 1; i < rows.length; i++) {
    const row = rows[i] ?? [];
    const stamp = text(row[columns.date]).match(stampRe);
    // The "Total" row and the summary below it carry no date.
    if (!stamp) continue;
    if (columns.status >= 0) {
      const status = text(row[columns.status]).toUpperCase();
      if (status && status !== 'COMPLETE') continue;
    }
    const description = tidy(text(row[columns.description]));
    const occurredAt = `${stamp[1]} ${stamp[2]}`;
    const debit = toAmount(text(row[columns.dr]));
    const credit = toAmount(text(row[columns.cr]));
    const ref = columns.ref >= 0 ? text(row[columns.ref]) : '';
    if (!description || (debit <= 0 && credit <= 0)) {
      skipped.push({
        row: i + 1,
        reason: !description ? 'No description' : 'No amount',
        text: row.map(text).filter((cell) => cell).join(' | ').slice(0, 120),
      });
      continue;
    }
    const base = ref ? { method: 'esewa', ref } : { method: 'esewa' };
    if (debit > 0) {
      entries.push({
        occurred_at: occurredAt,
        description,
        amount: debit,
        type: 'expense',
        ...base,
      });
    }
    if (credit > 0) {
      entries.push({
        occurred_at: occurredAt,
        description,
        amount: credit,
        type: 'income',
        ...base,
      });
    }
  }
  return entries;
}

// ---------------------------------------------------------------------------
// Generic bank spreadsheets (CSV / XLS / XLSX)
// ---------------------------------------------------------------------------

const MONTHS: Record<string, number> = {
  jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
  jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12,
};

const pad = (n: number) => String(n).padStart(2, '0');

/**
 * Reads the date formats bank exports use into `YYYY-MM-DD HH:MM:SS`.
 *
 * Returns `{ error }` rather than a guess when the text is not a date this
 * can be sure of. Day-first is assumed for `03/04/2026`, as in Nepal, unless
 * the numbers only make sense the other way round.
 */
export function parseStatementDate(
  raw: string,
  options: { allowBs?: boolean } = {},
): { stamp: string; bs?: boolean } | { error: string } {
  const text = raw.trim();
  if (!text) return { error: 'No date' };

  let year = 0, month = 0, day = 0;
  let rest = '';

  let m = text.match(/^(\d{4})[-\/.](\d{1,2})[-\/.](\d{1,2})(.*)$/);
  if (m) {
    year = +m[1]; month = +m[2]; day = +m[3]; rest = m[4];
  } else if ((m = text.match(/^(\d{1,2})[-\/.](\d{1,2})[-\/.](\d{2,4})(.*)$/))) {
    day = +m[1]; month = +m[2]; year = +m[3]; rest = m[4];
    if (month > 12 && day <= 12) [day, month] = [month, day];
  } else if ((m = text.match(/^(\d{1,2})[-\/\s]([A-Za-z]{3})[A-Za-z]*[-\/\s,]+(\d{2,4})(.*)$/))) {
    day = +m[1]; month = MONTHS[m[2].toLowerCase()] ?? 0; year = +m[3]; rest = m[4];
  } else if ((m = text.match(/^([A-Za-z]{3})[A-Za-z]*\s+(\d{1,2}),?\s+(\d{4})(.*)$/))) {
    month = MONTHS[m[1].toLowerCase()] ?? 0; day = +m[2]; year = +m[3]; rest = m[4];
  } else {
    return { error: 'Date not recognised' };
  }

  if (year < 100) year += 2000;
  // Bikram Sambat years run about 57 ahead. Converting them needs the
  // calendar tables, which the app has: the date is handed over as printed
  // and marked, never read as an AD date half a century in the future.
  const bs = year >= 2070 && year <= 2120;
  if (bs) {
    if (!options.allowBs) return { error: 'Bikram Sambat date' };
    if (month < 1 || month > 12 || day < 1 || day > 32) {
      return { error: 'Date not recognised' };
    }
  } else {
    if (year < 1990 || month < 1 || month > 12 || day < 1 || day > 31) {
      return { error: 'Date not recognised' };
    }
    const check = new Date(Date.UTC(year, month - 1, day));
    if (check.getUTCMonth() !== month - 1) {
      return { error: 'Date not recognised' };
    }
  }

  let hh = 0, mm = 0, ss = 0;
  const time = rest.match(/(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp][Mm])?/);
  if (time) {
    hh = +time[1]; mm = +time[2]; ss = time[3] ? +time[3] : 0;
    const half = time[4]?.toLowerCase();
    if (half === 'pm' && hh < 12) hh += 12;
    if (half === 'am' && hh === 12) hh = 0;
    if (hh > 23 || mm > 59 || ss > 59) { hh = 0; mm = 0; ss = 0; }
  }
  const stamp =
    `${year}-${pad(month)}-${pad(day)} ${pad(hh)}:${pad(mm)}:${pad(ss)}`;
  return bs ? { stamp, bs: true } : { stamp };
}

/**
 * A money cell as a number, with which way it points when the cell says so:
 * `1,250.00`, `Rs. 500`, `(75.00)`, `-75`, `120.00 Dr`. Null when the cell
 * holds something that is not an amount.
 */
export function parseMoneyCell(
  raw: string,
): { amount: number; sign: -1 | 0 | 1 } | null {
  let text = raw.trim();
  if (!text || text === '-' || text === '--') return { amount: 0, sign: 0 };
  let sign: -1 | 0 | 1 = 0;
  const suffix = text.match(/\s*(dr|cr)\.?$/i);
  if (suffix) {
    sign = suffix[1].toLowerCase() === 'dr' ? -1 : 1;
    text = text.slice(0, suffix.index).trim();
  }
  if (/^\(.*\)$/.test(text)) {
    sign = -1;
    text = text.slice(1, -1);
  }
  text = text.replace(/npr|rs\.?|रु\.?|₹/gi, '').replace(/[\s,]/g, '');
  if (text.startsWith('-')) {
    sign = -1;
    text = text.slice(1);
  } else if (text.startsWith('+')) {
    sign = 1;
    text = text.slice(1);
  }
  if (!/^\d+(\.\d+)?$/.test(text)) return null;
  const value = Math.round(parseFloat(text) * 100) / 100;
  if (!Number.isFinite(value)) return null;
  return { amount: value, sign };
}

type GenericColumn =
  | 'date' | 'description' | 'debit' | 'credit' | 'amount' | 'type' | 'ref'
  | 'status';

const HEADERS: Record<GenericColumn, RegExp> = {
  date: /^(transaction |txn |tran |posting |value )?date( ?time)?$|^date \(?ad\)?$|^miti$/,
  description:
    /^(transaction )?(description|particulars?|narration|remarks?|details?)$|^desc$|^(service|purpose|title|merchant|activity)( name)?$/,
  debit: /^(debit|withdraw(al)?s?|dr|paid out|money out)( amount)?( \(?(npr|rs)\)?)?$/,
  credit: /^(credit|deposits?|cr|paid in|money in)( amount)?( \(?(npr|rs)\)?)?$/,
  amount: /^(transaction |txn )?amount( \(?(npr|rs)\)?)?$/,
  type: /^(transaction |txn )?type$|^dr ?\/ ?cr$|^cr ?\/ ?dr$|^direction$/,
  ref: /^(reference|ref|transaction|txn|cheque|chq)( ?(code|no|number|id))?$/,
  status: /^(transaction |txn )?(status|state)$/,
};

/** A status that says the money did not move. */
const NOT_COMPLETED =
  /fail|cancel|pending|reject|declin|expired|error|unsuccess|incomplete|processing|initiated|ambiguous/i;

function headerKey(cell: unknown): string {
  return (cell == null ? '' : String(cell))
    .toLowerCase()
    .replace(/[.:_]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Reads a bank statement exported as a spreadsheet, whatever the bank.
 *
 * Nothing about a particular bank is assumed. The header row is found by its
 * column names, which may be anywhere near the top; the columns are then
 * read by name. A sheet whose columns cannot be identified yields nothing
 * rather than a guess, and a row that cannot be read is reported, not
 * invented.
 */
export function parseGenericRows(
  rows: unknown[][],
  skipped: SkippedRow[] = [],
  method?: string,
): StatementEntry[] {
  const text = (value: unknown) => (value == null ? '' : String(value).trim());

  let headerIndex = -1;
  let columns: Partial<Record<GenericColumn, number>> = {};
  for (let i = 0; i < Math.min(rows.length, 40); i++) {
    const found: Partial<Record<GenericColumn, number>> = {};
    (rows[i] ?? []).forEach((cell, index) => {
      const key = headerKey(cell);
      if (!key) return;
      for (const name of Object.keys(HEADERS) as GenericColumn[]) {
        if (found[name] === undefined && HEADERS[name].test(key)) {
          found[name] = index;
          return;
        }
      }
    });
    const hasMoney = (found.debit !== undefined && found.credit !== undefined) ||
      found.amount !== undefined;
    if (found.date !== undefined && hasMoney) {
      headerIndex = i;
      columns = found;
      break;
    }
  }
  if (headerIndex < 0) return [];

  const entries: StatementEntry[] = [];
  for (let i = headerIndex + 1; i < rows.length; i++) {
    const row = rows[i] ?? [];
    const cell = (name: GenericColumn) =>
      columns[name] === undefined ? '' : text(row[columns[name]!]);
    const line = row.map(text).filter((c) => c).join(' | ').slice(0, 120);
    if (!line) continue;

    const dateText = cell('date');
    const description = tidy(cell('description'));
    // Balance and total lines sit in the table but are not transactions.
    if (/^(opening|closing) balance|^total|^grand total|^balance (b\/f|c\/f)/i.test(description)) {
      continue;
    }
    if (!dateText) {
      // A footer or a wrapped description: nothing to import, nothing lost.
      continue;
    }
    const date = parseStatementDate(dateText, { allowBs: true });
    if ('error' in date) {
      skipped.push({ row: i + 1, reason: date.error, text: line });
      continue;
    }
    // A payment that failed or is still pending moved no money.
    if (NOT_COMPLETED.test(cell('status'))) continue;

    let debit = 0;
    let credit = 0;
    if (columns.debit !== undefined && columns.credit !== undefined) {
      const out = parseMoneyCell(cell('debit'));
      const into = parseMoneyCell(cell('credit'));
      if (out === null || into === null) {
        skipped.push({ row: i + 1, reason: 'Amount not recognised', text: line });
        continue;
      }
      debit = out.amount;
      credit = into.amount;
    } else {
      const money = parseMoneyCell(cell('amount'));
      if (money === null) {
        skipped.push({ row: i + 1, reason: 'Amount not recognised', text: line });
        continue;
      }
      let sign = money.sign;
      const kind = cell('type').toLowerCase();
      if (/^(dr|debit|withdraw|w$|d$|out|sent|paid|payment|expense)/.test(kind)) {
        sign = -1;
      } else if (
        /^(cr|credit|deposit|c$|in$|in |received|receive|load|income|refund|cashback)/
          .test(kind)
      ) {
        sign = 1;
      }
      if (money.amount > 0 && sign === 0) {
        // One amount column and nothing saying which way the money went.
        skipped.push({
          row: i + 1,
          reason: 'Cannot tell if this is money in or out',
          text: line,
        });
        continue;
      }
      if (sign < 0) debit = money.amount;
      else credit = money.amount;
    }

    if (debit <= 0 && credit <= 0) {
      skipped.push({ row: i + 1, reason: 'No amount', text: line });
      continue;
    }
    const ref = cell('ref');
    const label = description || (ref ? `Ref ${ref}` : 'Bank transaction');
    const extra = {
      ...(ref ? { ref } : {}),
      ...(method ? { method } : {}),
      ...('bs' in date && date.bs ? { calendar: 'bs' as const } : {}),
    };
    if (debit > 0) {
      entries.push({
        occurred_at: date.stamp,
        description: label,
        amount: debit,
        type: 'expense',
        ...extra,
      });
    }
    if (credit > 0) {
      entries.push({
        occurred_at: date.stamp,
        description: label,
        amount: credit,
        type: 'income',
        ...extra,
      });
    }
  }
  return entries;
}

/**
 * One spreadsheet cell as text the parsers can read.
 *
 * A real date cell arrives as a `Date` and is written out unambiguously as
 * `YYYY-MM-DD HH:MM:SS`. Letting the spreadsheet library format it instead
 * produces `3/2/26`, which cannot be told apart from the 3rd of February.
 */
export function cellText(value: unknown): string {
  if (value == null) return '';
  if (value instanceof Date) {
    if (Number.isNaN(value.getTime())) return '';
    // The library builds the date so that its local fields are the sheet's
    // wall-clock time; half a second is added to undo its rounding.
    const d = new Date(value.getTime() + 500);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
      `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }
  return String(value).trim();
}

/**
 * Reads any supported spreadsheet: the eSewa report when its header is
 * present, otherwise a generic bank export.
 */
export function parseSheet(
  rows: unknown[][],
  hint?: StatementSourceId,
): ParsedStatement {
  const skipped: SkippedRow[] = [];
  const isEsewa = rows.some((row) => {
    const labels = (row ?? []).map(headerKey);
    return labels.includes('date time') && labels.includes('dr') &&
      labels.includes('cr');
  });
  if (isEsewa) {
    return {
      entries: parseEsewaRows(rows, skipped),
      skipped,
      source: 'esewa',
      format: 'esewa-sheet',
      provider: 'eSewa',
    };
  }
  // The file's own words outrank what the user picked: a wallet names itself
  // in the lines above its table.
  const named = sheetSource(rows);
  const source: StatementSourceId = named ?? hint ?? 'bank';
  const method = source === 'khalti' || source === 'esewa' ? source : undefined;
  const entries = parseGenericRows(rows, skipped, method);
  return {
    entries,
    skipped,
    source: entries.length > 0 || skipped.length > 0 ? source : 'unknown',
    format: 'sheet',
  };
}

/** A wallet naming itself in the first lines of its export. */
function sheetSource(rows: unknown[][]): StatementSourceId | null {
  // Only the lines above the table: a bank statement mentions wallets in its
  // own rows ("KHALTI LOAD") without being a wallet statement.
  const above: string[] = [];
  for (const row of rows.slice(0, 40)) {
    const cells = (row ?? []).map((cell) => String(cell ?? ''));
    if (cells.some((cell) => HEADERS.date.test(headerKey(cell)))) break;
    above.push(cells.join(' '));
  }
  const top = above.join(' ').toLowerCase();
  if (/\bkhalti\b/.test(top)) return 'khalti';
  if (/\besewa\b/.test(top)) return 'esewa';
  return null;
}
