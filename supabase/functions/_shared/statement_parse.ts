// Pure row parsers for the statement importer. No I/O and no library imports,
// so they can be unit tested without a PDF or spreadsheet reader.
//
// Two layouts are understood:
//   * the bank "Electronic Account Statement" PDF
//       S.N | Transaction Date | Description | Withdraw | Deposit | Balance
//   * the eSewa "Statement Report" spreadsheet
//       Reference Code | Date Time | Description | Dr. | Cr. | Status | ...

export interface StatementEntry {
  occurred_at: string;
  description: string;
  amount: number;
  type: 'income' | 'expense';
  /** Set when the file itself says which wallet it is, e.g. `esewa`. */
  method?: string;
}

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
  return 'unknown';
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
export function parseEsewaRows(rows: unknown[][]): StatementEntry[] {
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
    if (!description) continue;

    const occurredAt = `${stamp[1]} ${stamp[2]}`;
    const debit = toAmount(text(row[columns.dr]));
    const credit = toAmount(text(row[columns.cr]));
    if (debit > 0) {
      entries.push({
        occurred_at: occurredAt,
        description,
        amount: debit,
        type: 'expense',
        method: 'esewa',
      });
    }
    if (credit > 0) {
      entries.push({
        occurred_at: occurredAt,
        description,
        amount: credit,
        type: 'income',
        method: 'esewa',
      });
    }
  }
  return entries;
}
