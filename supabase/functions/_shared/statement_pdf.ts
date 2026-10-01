// Reads a statement PDF from any bank or wallet, without knowing its layout
// in advance. No I/O and no library imports, so it is unit tested with plain
// lists of positioned text.
//
// A PDF has no table in it, only pieces of text with positions. The reader:
//   1. groups the text into lines by height on the page;
//   2. finds the table's heading row by what its cells are called (Date,
//      Particulars, Debit, Withdraw, Balance, ...), wherever it is;
//   3. reads each dated line under it, telling the columns apart by what a
//      cell contains first (a date, a money amount) and by where it sits
//      under the headings second;
//   4. checks the result against the statement's own running balance.
//
// Whatever cannot be read with confidence is reported, never guessed.

import {
  parseMoneyCell,
  parseStatementDate,
  type SkippedRow,
  type StatementEntry,
  type TextItem,
} from './statement_parse.ts';

export type PdfColumn =
  | 'sn' | 'date' | 'dateBs' | 'valueDate' | 'description' | 'ref'
  | 'debit' | 'credit' | 'amount' | 'type' | 'balance' | 'status' | 'other';

export interface PdfParseResult {
  entries: StatementEntry[];
  skipped: SkippedRow[];
  /** 1-based pages that had text but no transaction that could be read. */
  unreadPages: number[];
  /** The columns found, in order, e.g. `date, description, debit, credit`. */
  layout: string | null;
  /** `table` when a heading row was found, `lines` when rows were read bare. */
  format: 'table' | 'lines' | 'none';
  /** True when the amounts were confirmed against the running balance. */
  balanceChecked: boolean;
  /** Text printed above the table on the first page: the bank's own header. */
  preamble: string;
}

interface Cell {
  text: string;
  x0: number;
  x1: number;
}

interface Line {
  page: number;
  y: number;
  cells: Cell[];
  /** Every piece of text as its own cell, unjoined. */
  pieces: Cell[];
}

interface HeaderColumn {
  kind: PdfColumn;
  x0: number;
  x1: number;
}

/** A transaction line as read, before the balance check settles it. */
interface Row {
  page: number;
  y: number;
  stamp: string;
  bs: boolean;
  description: string[];
  ref: string;
  debit: number;
  credit: number;
  /** A single amount whose direction the row itself does not give. */
  loose: number | null;
  balance: number | null;
  text: string;
  check?: string;
}

/** Text on one line sits within this many points of the same height. */
const LINE_TOLERANCE = 3;
/** A wrapped description belongs to a row at most this far away. */
const WRAP_REACH = 26;
const CENT = 0.011;

// ---------------------------------------------------------------------------
// Lines and cells
// ---------------------------------------------------------------------------

/**
 * Some PDFs draw a whole line as one piece of text, with runs of spaces
 * between the columns. Those are cut back into separate pieces, placed in
 * proportion to where they sit in the string.
 */
function splitWide(item: TextItem): TextItem[] {
  if (!/\S\s{2,}\S/.test(item.str)) return [item];
  const total = item.str.length;
  const pieces: TextItem[] = [];
  const re = /\S+(?:\s\S+)*/g;
  let match: RegExpExecArray | null;
  while ((match = re.exec(item.str)) !== null) {
    pieces.push({
      str: match[0],
      x: item.x + (item.width * match.index) / total,
      y: item.y,
      width: (item.width * match[0].length) / total,
    });
  }
  return pieces.length > 0 ? pieces : [item];
}

function linesOf(items: TextItem[], page: number): Line[] {
  const clean = items
    .filter((item) => item.str.trim())
    .flatMap(splitWide)
    .sort((a, b) => a.y - b.y || a.x - b.x);
  const groups: { y: number; items: TextItem[] }[] = [];
  for (const item of clean) {
    const last = groups[groups.length - 1];
    if (last && Math.abs(item.y - last.y) <= LINE_TOLERANCE) {
      last.items.push(item);
    } else {
      groups.push({ y: item.y, items: [item] });
    }
  }
  return groups.map((group) => ({
    page,
    y: group.y,
    cells: cellsOf(group.items.sort((a, b) => a.x - b.x)),
    pieces: group.items
      .filter((item) => item.str.trim())
      .map((item) => ({
        text: item.str.trim(),
        x0: item.x,
        x1: item.x + item.width,
      })),
  }));
}

/** Joins the words of one cell, which a PDF often draws separately. */
function cellsOf(items: TextItem[]): Cell[] {
  const cells: Cell[] = [];
  for (const item of items) {
    const text = item.str.trim();
    if (!text) continue;
    const x0 = item.x;
    const x1 = item.x + item.width;
    const charWidth = item.width > 0 ? item.width / item.str.length : 4;
    const last = cells[cells.length - 1];
    // Two amounts side by side are two columns, however tightly they are
    // printed: "50.00" and "0.00" must never become one cell.
    const twoNumbers = last !== undefined &&
      /\d\.?\)?$/.test(last.text) && /^[-+(]?\s*(npr|rs\.?)?\s*\d/i.test(text) &&
      (looksLikeMoney(text) || looksLikeMoney(last.text.split(' ').pop() ?? ''));
    // A space between words is about one character wide; the gap between two
    // columns is wider than that.
    if (last && !twoNumbers && x0 - last.x1 < Math.max(charWidth * 1.3, 2.5)) {
      last.text += x0 - last.x1 > charWidth * 0.25 ? ` ${text}` : text;
      last.x1 = Math.max(last.x1, x1);
    } else {
      cells.push({ text, x0, x1 });
    }
  }
  return cells;
}

const lineText = (line: Line) => line.cells.map((cell) => cell.text).join(' ');

// ---------------------------------------------------------------------------
// The heading row
// ---------------------------------------------------------------------------

function headingKey(text: string): string {
  return text
    .toLowerCase()
    .replace(/[.:_*]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// Tried in order: the first that matches names the column.
const HEADINGS: [PdfColumn, RegExp][] = [
  ['valueDate', /^(value|val|effective) ?date/],
  ['dateBs', /miti|\bb ?s\b|nepali date/],
  [
    'date',
    /^((transaction|trans|tran|txn|trn|posting|post|posted|entry|booking) )?date( ?(and |& )?time)?( \(?a ?d\)?)?$|^(transaction|txn|tran) time$/,
  ],
  ['type', /^((transaction|txn|tran) )?type$|^dr ?\/ ?cr$|^cr ?\/ ?dr$/],
  ['balance', /balance|^bal$/],
  ['debit', /^(debit|withdraw|dr\b|paid out|money out)/],
  ['credit', /^(credit|deposit|cr\b|paid in|money in)/],
  ['amount', /^((transaction|txn|tran) )?(amount|amt)\b/],
  ['description', /description|particular|narration|remark|detail|^desc$/],
  [
    'ref',
    /\bref|che?que|\bchq|instrument|voucher|(txn|tran|transaction) ?(id|no|number|code)$/,
  ],
  ['sn', /^(s ?n|s ?no|sr|sr no|sl|sl no|no|#)$/],
  ['status', /^(transaction |txn )?(status|state)$/],
];

function columnKind(text: string): PdfColumn {
  const key = headingKey(text);
  if (!key) return 'other';
  for (const [kind, pattern] of HEADINGS) {
    if (pattern.test(key)) return kind;
  }
  return 'other';
}

function isMoneyKind(kind: PdfColumn): boolean {
  return kind === 'debit' || kind === 'credit' || kind === 'amount' ||
    kind === 'balance';
}

function asHeader(cells: Cell[]): HeaderColumn[] | null {
  const columns = cells
    .map((cell) => ({ kind: columnKind(cell.text), x0: cell.x0, x1: cell.x1 }))
    .sort((a, b) => a.x0 - b.x0);
  const has = (kind: PdfColumn) => columns.some((c) => c.kind === kind);
  const named = columns.filter((c) => c.kind !== 'other').length;
  const dated = has('date') || has('dateBs');
  const money = (has('debit') && has('credit')) || has('amount');
  // A heading names its columns; a line of a transaction never does.
  if (!dated || !money || named < 3) return null;
  // Each kind once: a second "Debit" would mean this is not a heading row.
  const seen = new Set<PdfColumn>();
  for (const column of columns) {
    if (column.kind === 'other') continue;
    if (seen.has(column.kind)) return null;
    seen.add(column.kind);
  }
  return columns;
}

/** Headings that wrap onto a second line: "Withdraw" over "Amount". */
function stacked(top: Cell[], bottom: Cell[]): Cell[] {
  const merged = top.map((cell) => ({ ...cell }));
  for (const lower of bottom) {
    const over = merged.find(
      (cell) => Math.min(cell.x1, lower.x1) - Math.max(cell.x0, lower.x0) > 0,
    );
    if (over) {
      over.text += ` ${lower.text}`;
      over.x0 = Math.min(over.x0, lower.x0);
      over.x1 = Math.max(over.x1, lower.x1);
    } else {
      merged.push({ ...lower });
    }
  }
  return merged.sort((a, b) => a.x0 - b.x0);
}

const HEADING_WORD =
  /^\(?(amount|amt|no|number|id|date|time|details?|npr|nrs|rs|in npr|dr|cr)\.?\)?$/i;

/**
 * True when [line] is the second line of the heading above it: only heading
 * words, each sitting under one of the headings.
 */
function continuesHeader(line: Line, header: HeaderColumn[]): boolean {
  if (line.cells.length === 0 || line.cells.length > header.length) return false;
  return line.cells.every((cell) =>
    (HEADING_WORD.test(cell.text.trim()) || columnKind(cell.text) !== 'other') &&
    header.some(
      (column) =>
        Math.min(column.x1, cell.x1) - Math.max(column.x0, cell.x0) > 0,
    )
  );
}

// ---------------------------------------------------------------------------
// Cells of a transaction line
// ---------------------------------------------------------------------------

const DATE_PREFIXES: RegExp[] = [
  /^\d{4}[-\/.]\d{1,2}[-\/.]\d{1,2}/,
  /^\d{1,2}[-\/.]\d{1,2}[-\/.]\d{2,4}/,
  /^\d{1,2}[-\/\s][A-Za-z]{3,9}[-\/\s,]+\d{2,4}/,
  /^[A-Za-z]{3,9}\s+\d{1,2},?\s+\d{4}/,
];
// Seconds may carry a fraction, as eSewa writes them: 10:00:00.0
const TIME_PREFIX =
  /^[\sT,]*\d{1,2}:\d{2}(:\d{2}(\.\d{1,6})?)?(\s*[AaPp][Mm])?/;
const TIME_ONLY = /^\d{1,2}:\d{2}(:\d{2}(\.\d{1,6})?)?(\s*[AaPp][Mm])?$/;

/**
 * Splits a date (and a time, if one follows) off the front of a cell.
 * Returns the date text and whatever came after it.
 */
export function leadingDate(
  text: string,
): { date: string; rest: string } | null {
  const trimmed = text.trim();
  for (const pattern of DATE_PREFIXES) {
    const match = trimmed.match(pattern);
    if (!match) continue;
    let end = match[0].length;
    const time = trimmed.slice(end).match(TIME_PREFIX);
    if (time) end += time[0].length;
    // "2025-01-15abc" is not a date followed by text.
    const next = trimmed.charAt(end);
    if (next && !/[\s,|;]/.test(next)) continue;
    return { date: trimmed.slice(0, end), rest: trimmed.slice(end).trim() };
  }
  return null;
}

const MONEY_SHAPE =
  /^\(?[-+]?\s*(npr|nrs|rs)?\.?\s*\d[\d,]*(\.\d{1,2})?\)?(\s*(dr|cr)\.?)?$/i;

/** Text that is an amount of money as statements print it: `1,250.00`. */
function looksLikeMoney(text: string): boolean {
  const t = text.trim();
  return MONEY_SHAPE.test(t) && /[.,]\d/.test(t);
}

function isPlaceholder(text: string): boolean {
  return /^[-–—]+$/.test(text.trim());
}

function centre(cell: { x0: number; x1: number }): number {
  return (cell.x0 + cell.x1) / 2;
}

/**
 * How far a cell is from lining up with a heading. Numbers are usually
 * right-aligned and text left-aligned, under headings that may be centred,
 * so the best of the three alignments is taken.
 */
function alignment(cell: Cell, column: HeaderColumn): number {
  return Math.min(
    Math.abs(centre(cell) - centre(column)),
    Math.abs(cell.x1 - column.x1),
    Math.abs(cell.x0 - column.x0),
  );
}

/** The heading whose stretch of the page the middle of [cell] falls in. */
function territory(cell: Cell, header: HeaderColumn[]): HeaderColumn {
  const x = centre(cell);
  for (let i = 0; i < header.length - 1; i++) {
    if (x < (header[i].x1 + header[i + 1].x0) / 2) return header[i];
  }
  return header[header.length - 1];
}

function nearestMoney(cell: Cell, header: HeaderColumn[]): HeaderColumn | null {
  let best: HeaderColumn | null = null;
  for (const column of header) {
    if (!isMoneyKind(column.kind)) continue;
    if (!best || alignment(cell, column) < alignment(cell, best)) best = column;
  }
  return best;
}

const NOT_COMPLETED =
  /fail|cancel|pending|reject|declin|expired|error|unsuccess|incomplete|processing|initiated|ambiguous|reversed/i;

const NOT_A_TRANSACTION =
  /^(opening|closing) balance|^balance (b\/?f|c\/?f|brought|carried)|^(b\/f|c\/f)\b|brought forward|carried forward|^(grand |sub ?)?total\b|^page \d+/i;
const OPENING = /opening balance|balance b\/?f|brought forward|^b\/f\b/i;

function tidy(text: string): string {
  return text.replace(/\s+/g, ' ').replace(/[\s,\-:|]+$/, '').trim();
}

function signedBalance(text: string): number | null {
  const money = parseMoneyCell(text);
  if (money === null) return null;
  return money.sign < 0 ? -money.amount : money.amount;
}

/** Reads one dated line of the table. Null when the line is not a row. */
function readRow(
  line: Line,
  header: HeaderColumn[],
  skipped: SkippedRow[],
): Row | 'opening' | null {
  const text = lineText(line);

  const dates: { stamp: string; bs: boolean }[] = [];
  let dateSeen = 0;
  // Whether the line's first date sits where the table keeps its dates. A
  // date anywhere else ("From Date : 2026-01-01" in a page heading) does not
  // make the line a transaction.
  let dateInPlace = false;
  let time = '';
  const description: string[] = [];
  let ref = '';
  let type = '';
  let status = '';
  const money: Record<'debit' | 'credit' | 'amount' | 'balance', string[]> = {
    debit: [],
    credit: [],
    amount: [],
    balance: [],
  };

  for (const original of line.cells) {
    let cell = original;
    const home = territory(cell, header);

    const dated = leadingDate(cell.text);
    if (dated) {
      const parsed = parseStatementDate(dated.date, { allowBs: true });
      if (dateSeen === 0) {
        dateInPlace = home.kind === 'date' || home.kind === 'dateBs' ||
          home.kind === 'valueDate' || home.kind === 'sn';
      }
      dateSeen++;
      // A value date is when the bank settled it, not when it happened.
      if (!('error' in parsed) && home.kind !== 'valueDate') {
        dates.push({ stamp: parsed.stamp, bs: parsed.bs === true });
      }
      if (!dated.rest) continue;
      // Text after the date in the same cell is the start of the description.
      cell = { ...cell, text: dated.rest };
      if (!looksLikeMoney(cell.text)) {
        description.push(cell.text);
        continue;
      }
    }

    if (TIME_ONLY.test(cell.text) && dateSeen > 0 && !time) {
      time = cell.text;
      continue;
    }

    if (looksLikeMoney(cell.text)) {
      const column = nearestMoney(cell, header);
      if (column) {
        money[column.kind as keyof typeof money].push(cell.text);
        continue;
      }
    }
    if (isPlaceholder(cell.text) && isMoneyKind(home.kind)) continue;

    switch (home.kind) {
      case 'ref':
        ref = ref ? `${ref} ${cell.text}` : cell.text;
        break;
      case 'type':
        type = cell.text;
        break;
      case 'sn':
        // A serial number; anything else in that corner is description.
        if (!/^\d{1,5}\.?$/.test(cell.text)) description.push(cell.text);
        break;
      case 'debit':
      case 'credit':
      case 'amount':
      case 'balance':
        // A whole number with no decimals, sitting under a money heading.
        if (/^[\d,]+$/.test(cell.text)) {
          money[home.kind].push(cell.text);
        } else if (/^(dr|cr)\.?$/i.test(cell.text)) {
          const list = money[home.kind];
          if (list.length > 0) list[list.length - 1] += ` ${cell.text}`;
          else type = cell.text;
        } else {
          description.push(cell.text);
        }
        break;
      case 'status':
        status = status ? `${status} ${cell.text}` : cell.text;
        break;
      case 'other':
        break;
      default:
        description.push(cell.text);
    }
  }

  // The first date on the line is the transaction's. A statement that prints
  // both calendars is read in AD, which needs no conversion.
  const chosen = dates.find((date) => !date.bs) ?? dates[0];
  let stamp = chosen?.stamp ?? '';
  const bs = chosen?.bs ?? false;
  if (stamp && time && stamp.endsWith('00:00:00')) {
    const timed = parseStatementDate(`${stamp.slice(0, 10)} ${time}`, {
      allowBs: true,
    });
    if (!('error' in timed)) stamp = timed.stamp;
  }

  const anyMoney = money.debit.length + money.credit.length +
    money.amount.length + money.balance.length > 0;
  if (!dateInPlace && !anyMoney) return null;

  if (!stamp) {
    // A line with a date in it that could not be read is worth reporting; a
    // line with no date at all is a heading, a footer or wrapped text.
    if (dateSeen > 0) {
      skipped.push({
        row: 0,
        page: line.page,
        reason: 'Date not recognised',
        text: text.slice(0, 120),
      });
    }
    return null;
  }

  const label = tidy(description.join(' '));
  if (OPENING.test(label)) return 'opening';
  // A payment that failed or is still pending moved no money.
  if (NOT_COMPLETED.test(status)) return null;
  if (NOT_A_TRANSACTION.test(label)) return null;

  const amountOf = (cells: string[]) => {
    if (cells.length === 0) return { amount: 0, sign: 0 as -1 | 0 | 1 };
    if (cells.length > 1) return null;
    return parseMoneyCell(cells[0]);
  };
  const debit = amountOf(money.debit);
  const credit = amountOf(money.credit);
  const single = amountOf(money.amount);
  const balance = money.balance.length === 1
    ? signedBalance(money.balance[0])
    : null;
  if (debit === null || credit === null || single === null) {
    skipped.push({
      row: 0,
      page: line.page,
      reason: 'Amount not recognised',
      text: text.slice(0, 120),
    });
    return null;
  }

  const row: Row = {
    page: line.page,
    y: line.y,
    stamp,
    bs,
    description: label ? [label] : [],
    ref: tidy(ref),
    debit: debit.amount,
    credit: credit.amount,
    loose: null,
    balance,
    text: text.slice(0, 120),
  };

  if (single.amount > 0 && row.debit === 0 && row.credit === 0) {
    let sign = single.sign;
    const kind = type.toLowerCase();
    if (/^(dr|debit|withdraw|out|sent|paid|payment)/.test(kind)) sign = -1;
    else if (/^(cr|credit|deposit|in|received|load)/.test(kind)) sign = 1;
    if (sign < 0) row.debit = single.amount;
    else if (sign > 0) row.credit = single.amount;
    else row.loose = single.amount;
  }

  if (row.debit <= 0 && row.credit <= 0 && row.loose === null) {
    skipped.push({
      row: 0,
      page: line.page,
      reason: 'No amount',
      text: text.slice(0, 120),
    });
    return null;
  }
  return row;
}

// ---------------------------------------------------------------------------
// The running balance
// ---------------------------------------------------------------------------

const near = (a: number, b: number) => Math.abs(a - b) < CENT;

function fits(row: Row, delta: number): boolean {
  if (row.loose !== null) return near(Math.abs(delta), row.loose);
  return near(delta, row.credit - row.debit);
}

/**
 * Uses the statement's own Balance column as a check on what was read.
 *
 * A statement lists either oldest or newest first; whichever order makes the
 * balances add up is the one it uses. Once the balances are seen to add up
 * for most of the statement, a row that does not is marked for the user to
 * look at, and a row whose direction the statement does not print is given
 * the direction its balance shows. Without that confirmation nothing is
 * inferred.
 */
function settle(
  rows: Row[],
  opening: number | null,
  skipped: SkippedRow[],
  mustVerify: boolean,
): { rows: Row[]; checked: boolean } {
  let forward = 0;
  let backward = 0;
  let pairs = 0;
  for (let i = 1; i < rows.length; i++) {
    const a = rows[i - 1].balance;
    const b = rows[i].balance;
    if (a === null || b === null) continue;
    pairs++;
    if (fits(rows[i], b - a)) forward++;
    if (fits(rows[i - 1], a - b)) backward++;
  }
  const best = Math.max(forward, backward);
  const checked = pairs >= 2 && best >= Math.max(2, pairs * 0.8);
  const oldestFirst = forward >= backward;

  const kept: Row[] = [];
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const neighbour = oldestFirst ? rows[i - 1] : rows[i + 1];
    let before: number | null = neighbour ? neighbour.balance : null;
    if (!neighbour && oldestFirst && opening !== null) before = opening;
    const delta = row.balance !== null && before !== null
      ? row.balance - before
      : null;

    if (row.loose !== null) {
      if (checked && delta !== null && near(Math.abs(delta), row.loose)) {
        if (delta < 0) row.debit = row.loose;
        else row.credit = row.loose;
        row.loose = null;
      } else {
        skipped.push({
          row: 0,
          page: row.page,
          reason: 'Cannot tell if this is money in or out',
          text: row.text,
        });
        continue;
      }
    } else if (checked && delta !== null && !fits(row, delta)) {
      row.check = 'Does not match the running balance on the statement';
    }
    kept.push(row);
  }
  if (mustVerify && !checked) return { rows: [], checked: false };
  return { rows: kept, checked };
}

function toEntries(rows: Row[]): StatementEntry[] {
  const entries: StatementEntry[] = [];
  for (const row of rows) {
    const description = tidy(row.description.join(' ')) ||
      (row.ref ? `Ref ${row.ref}` : 'Bank transaction');
    const base = {
      occurred_at: row.stamp,
      description,
      ...(row.ref ? { ref: row.ref } : {}),
      ...(row.bs ? { calendar: 'bs' as const } : {}),
      ...(row.balance !== null ? { balance: row.balance } : {}),
      ...(row.check ? { check: row.check } : {}),
    };
    if (row.debit > 0) {
      entries.push({ ...base, amount: row.debit, type: 'expense' });
    }
    if (row.credit > 0) {
      entries.push({ ...base, amount: row.credit, type: 'income' });
    }
  }
  return entries;
}

// ---------------------------------------------------------------------------
// Reading a statement
// ---------------------------------------------------------------------------

/**
 * A line of wrapped description goes to the transaction it is nearest to:
 * usually the one above it, but the one below when a bank centres the date
 * and amounts against a description several lines tall.
 */
function attachWrapped(
  rows: Row[],
  loose: { page: number; y: number; text: string }[],
): void {
  for (const piece of loose) {
    let best: Row | null = null;
    let bestGap = WRAP_REACH;
    let below = false;
    for (const row of rows) {
      if (row.page !== piece.page) continue;
      const gap = Math.abs(row.y - piece.y);
      // Ties go to the row above, the ordinary top-aligned case.
      if (gap < bestGap - 0.5 || (gap < bestGap + 0.5 && row.y < piece.y)) {
        best = row;
        bestGap = gap;
        below = row.y > piece.y;
      }
    }
    if (!best) continue;
    if (below) best.description.unshift(piece.text);
    else best.description.push(piece.text);
  }
}

function readTable(pages: TextItem[][]): PdfParseResult | null {
  const skipped: SkippedRow[] = [];
  const rows: Row[] = [];
  const wrapped: { page: number; y: number; text: string }[] = [];
  const pagesWithRows = new Set<number>();
  const pagesWithText: number[] = [];
  let header: HeaderColumn[] | null = null;
  let layout: string | null = null;
  let opening: number | null = null;
  const preamble: string[] = [];

  pages.forEach((items, index) => {
    const page = index + 1;
    const lines = linesOf(items, page);
    if (lines.length > 0) pagesWithText.push(page);

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      // Narrow columns printed close together ("Dr." "Cr.") can be joined
      // into one cell; the pieces as drawn are tried too.
      let found = asHeader(line.cells) ?? asHeader(line.pieces);
      if (!found && i + 1 < lines.length && lines[i + 1].y - line.y < 18) {
        found = asHeader(stacked(line.cells, lines[i + 1].cells)) ??
          asHeader(stacked(line.pieces, lines[i + 1].pieces));
        if (found) i++;
      } else if (
        found && i + 1 < lines.length && lines[i + 1].y - line.y < 18 &&
        continuesHeader(lines[i + 1], found)
      ) {
        // "Withdrawal" over "Amount": the second line names no new column.
        i++;
      }
      if (found) {
        header = found;
        layout ??= found
          .filter((column) => column.kind !== 'other')
          .map((column) => column.kind)
          .join(', ');
        continue;
      }
      if (!header) {
        if (page === 1) preamble.push(lineText(line));
        continue;
      }

      const row = readRow(line, header, skipped);
      if (row === 'opening') {
        const cells = line.cells.filter((cell) => looksLikeMoney(cell.text));
        const last = cells[cells.length - 1];
        if (last && rows.length === 0) opening = signedBalance(last.text);
        continue;
      }
      if (row) {
        rows.push(row);
        pagesWithRows.add(page);
        continue;
      }
      // Not a row: wrapped description, if it is only text sitting where the
      // description goes.
      const text = lineText(line);
      if (
        leadingDate(text) === null &&
        !NOT_A_TRANSACTION.test(text) &&
        !line.cells.some((cell) => looksLikeMoney(cell.text)) &&
        line.cells.every((cell) => {
          const kind = territory(cell, header!).kind;
          return kind !== 'ref' && kind !== 'other' && kind !== 'type';
        })
      ) {
        wrapped.push({ page, y: line.y, text: tidy(text) });
      }
    }
  });

  if (!header) return null;
  attachWrapped(rows, wrapped);
  const settled = settle(rows, opening, skipped, false);
  return {
    entries: toEntries(settled.rows),
    skipped,
    unreadPages: pagesWithText.filter((page) => !pagesWithRows.has(page)),
    layout,
    format: 'table',
    balanceChecked: settled.checked,
    preamble: preamble.join('\n'),
  };
}

/**
 * For a statement with no heading row to go by: each line that starts with a
 * date and ends in an amount and a balance. Which way the money went is
 * taken from the balance, so this is only trusted when the balances add up.
 */
function readLines(pages: TextItem[][]): PdfParseResult | null {
  const skipped: SkippedRow[] = [];
  const rows: Row[] = [];
  const pagesWithRows = new Set<number>();
  const pagesWithText: number[] = [];
  const preamble: string[] = [];
  let opening: number | null = null;

  pages.forEach((items, index) => {
    const page = index + 1;
    const lines = linesOf(items, page);
    if (lines.length > 0) pagesWithText.push(page);
    for (const line of lines) {
      const text = lineText(line);
      const dated = leadingDate(text);
      if (!dated) {
        if (page === 1 && rows.length === 0) preamble.push(text);
        continue;
      }
      const parsed = parseStatementDate(dated.date, { allowBs: true });
      if ('error' in parsed) continue;

      const words = dated.rest.split(/\s+/).filter((word) => word);
      const amounts: string[] = [];
      while (words.length > 0) {
        const word = words[words.length - 1];
        if (/^(dr|cr)\.?$/i.test(word) && amounts.length > 0) {
          amounts[0] += ` ${words.pop()}`;
          continue;
        }
        if (/^(dr|cr)\.?$/i.test(word) && words.length > 1 &&
          looksLikeMoney(words[words.length - 2])) {
          const suffix = words.pop()!;
          amounts.unshift(`${words.pop()} ${suffix}`);
          continue;
        }
        if (!looksLikeMoney(word)) break;
        amounts.unshift(words.pop()!);
      }
      const label = tidy(words.join(' '));
      if (amounts.length < 2 || NOT_A_TRANSACTION.test(label)) continue;

      const balance = signedBalance(amounts[amounts.length - 1]);
      const row: Row = {
        page,
        y: line.y,
        stamp: parsed.stamp,
        bs: 'bs' in parsed && parsed.bs === true,
        description: label ? [label] : [],
        ref: '',
        debit: 0,
        credit: 0,
        loose: null,
        balance,
        text: text.slice(0, 120),
      };
      if (amounts.length === 2) {
        const money = parseMoneyCell(amounts[0]);
        if (money === null) continue;
        if (money.amount <= 0) {
          // Nothing moved: a balance carried over, which seeds the check.
          if (rows.length === 0) opening = balance;
          continue;
        }
        if (money.sign < 0) row.debit = money.amount;
        else if (money.sign > 0) row.credit = money.amount;
        else row.loose = money.amount;
      } else {
        // Three amounts: withdrawal, deposit, balance, one of the first two
        // being nil.
        const out = parseMoneyCell(amounts[amounts.length - 3]);
        const into = parseMoneyCell(amounts[amounts.length - 2]);
        if (out === null || into === null) continue;
        if (out.amount > 0 && into.amount > 0) {
          skipped.push({
            row: 0,
            page,
            reason: 'Cannot tell which amount is which',
            text: row.text,
          });
          continue;
        }
        row.debit = out.amount;
        row.credit = into.amount;
        if (row.debit <= 0 && row.credit <= 0) continue;
      }
      rows.push(row);
      pagesWithRows.add(page);
    }
  });

  if (rows.length < 3) return null;
  const settled = settle(rows, opening, skipped, true);
  if (settled.rows.length === 0) return null;
  return {
    entries: toEntries(settled.rows),
    skipped,
    unreadPages: pagesWithText.filter((page) => !pagesWithRows.has(page)),
    layout: null,
    format: 'lines',
    balanceChecked: settled.checked,
    preamble: preamble.join('\n'),
  };
}

/** Reads a statement PDF given as the positioned text of each page. */
export function parseStatementPdf(pages: TextItem[][]): PdfParseResult {
  const table = readTable(pages);
  if (table && table.entries.length > 0) return table;
  const lines = readLines(pages);
  if (lines) return lines;
  return table ?? {
    entries: [],
    skipped: [],
    unreadPages: pages
      .map((items, index) => (items.some((i) => i.str.trim()) ? index + 1 : 0))
      .filter((page) => page > 0),
    layout: null,
    format: 'none',
    balanceChecked: false,
    preamble: '',
  };
}
