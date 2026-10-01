import { assertEquals } from 'jsr:@std/assert@1';
import {
  parseSheet,
  type StatementEntry,
  type TextItem,
} from '../_shared/statement_parse.ts';
import { leadingDate, parseStatementPdf } from '../_shared/statement_pdf.ts';
import { detectProvider, readStatement } from '../_shared/statement_formats.ts';

// Text is laid out the way a PDF draws a table: every cell its own piece,
// about 5 points a character.
const W = 5;
const left = (str: string, x: number, y: number): TextItem => ({
  str,
  x,
  y,
  width: str.length * W,
});
const right = (str: string, edge: number, y: number): TextItem => ({
  str,
  x: edge - str.length * W,
  y,
  width: str.length * W,
});
const mid = (str: string, centre: number, y: number): TextItem => ({
  str,
  x: centre - (str.length * W) / 2,
  y,
  width: str.length * W,
});

const brief = (entries: StatementEntry[]) =>
  entries.map((e) => [e.occurred_at.slice(0, 10), e.type, e.amount, e.description]);

// ---------------------------------------------------------------------------
// Layout A: day-first dates, a cheque column, centred headings over
// right-aligned numbers, empty cells left blank, oldest first.
// ---------------------------------------------------------------------------
function layoutA(): TextItem[][] {
  const head = (y: number) => [
    mid('Date', 60, y),
    mid('Particulars', 190, y),
    mid('Cheque No', 320, y),
    mid('Debit', 400, y),
    mid('Credit', 480, y),
    mid('Balance', 560, y),
  ];
  const row = (
    y: number,
    date: string,
    text: string,
    debit: string,
    credit: string,
    balance: string,
    cheque = '',
  ) => [
    left(date, 36, y),
    left(text, 100, y),
    ...(cheque ? [left(cheque, 300, y)] : []),
    ...(debit ? [right(debit, 430, y)] : []),
    ...(credit ? [right(credit, 510, y)] : []),
    right(balance, 590, y),
  ];
  return [[
    left('Global IME Bank Limited', 200, 40),
    left('Statement of Account', 210, 56),
    left('Account Number: 0123456789', 36, 80),
    ...head(120),
    left('01/01/2025', 36, 140),
    left('Opening Balance', 100, 140),
    right('10,000.00', 590, 140),
    ...row(160, '02/01/2025', 'ATM WDL THAMEL', '2,000.00', '', '8,000.00'),
    ...row(180, '05/01/2025', 'SALARY JAN', '', '45,000.00', '53,000.00'),
    left('ACME PVT LTD', 100, 190),
    ...row(210, '07/01/2025', 'CHQ PAID', '1,250.50', '', '51,749.50', '004512'),
    ...row(230, '09/01/2025', 'FONEPAY QR MART', '749.50', '', '51,000.00'),
    left('Closing Balance', 100, 250),
    right('51,000.00', 590, 250),
  ]];
}

Deno.test('PDF layout A: columns are told apart without fixed positions', () => {
  const parsed = parseStatementPdf(layoutA());
  assertEquals(parsed.format, 'table');
  assertEquals(parsed.layout, 'date, description, ref, debit, credit, balance');
  assertEquals(brief(parsed.entries), [
    ['2025-01-02', 'expense', 2000, 'ATM WDL THAMEL'],
    // The wrapped second line joined its own row.
    ['2025-01-05', 'income', 45000, 'SALARY JAN ACME PVT LTD'],
    ['2025-01-07', 'expense', 1250.5, 'CHQ PAID'],
    ['2025-01-09', 'expense', 749.5, 'FONEPAY QR MART'],
  ]);
  assertEquals(parsed.entries[2].ref, '004512');
  assertEquals(parsed.entries.map((e) => e.balance), [8000, 53000, 51749.5, 51000]);
  // The statement's own balances confirm every amount, the opening balance
  // included, so nothing is marked for checking.
  assertEquals(parsed.balanceChecked, true);
  assertEquals(parsed.entries.filter((e) => e.check).length, 0);
  assertEquals(parsed.skipped, []);
  assertEquals(parsed.unreadPages, []);
});

// ---------------------------------------------------------------------------
// Layout B: month names, a value date, headings on two lines, newest first,
// "Cr" after the balance, a heading repeated on page two and a last page of
// small print.
// ---------------------------------------------------------------------------
function layoutB(): TextItem[][] {
  const head = (y: number) => [
    left('Tran Date', 30, y),
    left('Value Date', 95, y),
    left('Description', 165, y),
    left('Ref No', 330, y),
    right('Withdrawal', 440, y),
    right('Amount', 440, y + 10),
    right('Deposit', 510, y),
    right('Amount', 510, y + 10),
    right('Balance', 590, y),
  ];
  const row = (
    y: number,
    date: string,
    text: string,
    ref: string,
    out: string,
    into: string,
    balance: string,
  ) => [
    left(date, 30, y),
    left(date, 95, y),
    left(text, 165, y),
    left(ref, 330, y),
    right(out || '0.00', 440, y),
    right(into || '0.00', 510, y),
    right(`${balance} Cr`, 590, y),
  ];
  return [
    [
      left('NABIL BANK LIMITED', 220, 40),
      ...head(100),
      ...row(130, '20-Jan-2025', 'eSewa Wallet Load', 'FT25020881', '1,500.00', '', '20,300.00'),
      ...row(150, '18-Jan-2025', 'IPS/Remit Received', 'IPS998812', '', '12,000.00', '21,800.00'),
      left('Page 1 of 3', 280, 800),
    ],
    [
      ...head(60),
      ...row(90, '15-Jan-2025', 'POS Bhatbhateni', 'POS771200', '4,200.00', '', '9,800.00'),
      ...row(110, '12-Jan-2025', 'Interest Credit', 'INT000012', '', '35.75', '14,000.00'),
      left('Page 2 of 3', 280, 800),
    ],
    [
      left('This is a computer generated statement.', 100, 60),
      left('Please report any discrepancy within 15 days.', 100, 76),
    ],
  ];
}

Deno.test('PDF layout B: two-line headings, value dates, newest first, pages', () => {
  const parsed = parseStatementPdf(layoutB());
  assertEquals(
    parsed.layout,
    'date, valueDate, description, ref, debit, credit, balance',
  );
  assertEquals(brief(parsed.entries), [
    ['2025-01-20', 'expense', 1500, 'eSewa Wallet Load'],
    ['2025-01-18', 'income', 12000, 'IPS/Remit Received'],
    ['2025-01-15', 'expense', 4200, 'POS Bhatbhateni'],
    ['2025-01-12', 'income', 35.75, 'Interest Credit'],
  ]);
  assertEquals(parsed.entries.map((e) => e.ref), [
    'FT25020881',
    'IPS998812',
    'POS771200',
    'INT000012',
  ]);
  assertEquals(parsed.balanceChecked, true);
  assertEquals(parsed.entries.filter((e) => e.check).length, 0);
  // The page of small print is reported, not passed over silently.
  assertEquals(parsed.unreadPages, [3]);
});

Deno.test('the two layouts are not read from the same positions', () => {
  // The Debit column of one is where the Ref column of the other is.
  const a = layoutA()[0].find((i) => i.str === 'Debit')!;
  const b = layoutB()[0].find((i) => i.str === 'Ref No')!;
  assertEquals(Math.abs(a.x + a.width / 2 - (b.x + b.width / 2)) < 60, true);
});

// ---------------------------------------------------------------------------
// One Amount column
// ---------------------------------------------------------------------------
Deno.test('PDF: one Amount column with a Dr/Cr column', () => {
  const y = (n: number) => 100 + n * 20;
  const row = (n: number, d: string, t: string, a: string, k: string, b: string) => [
    left(d, 30, y(n)),
    left(t, 120, y(n)),
    right(a, 400, y(n)),
    left(k, 430, y(n)),
    right(b, 560, y(n)),
  ];
  const parsed = parseStatementPdf([[
    left('Date', 30, 100),
    left('Narration', 120, 100),
    right('Amount', 400, 100),
    left('Dr/Cr', 425, 100),
    right('Balance', 560, 100),
    ...row(1, '2025-02-01', 'Mobile topup', '500.00', 'Dr', '4,500.00'),
    ...row(2, '2025-02-03', 'Cash deposit', '2,000.00', 'Cr', '6,500.00'),
    ...row(3, '2025-02-04', 'NPR fee', 'NPR 25.00', 'DR', '6,475.00'),
  ]]);
  assertEquals(parsed.layout, 'date, description, amount, type, balance');
  assertEquals(brief(parsed.entries), [
    ['2025-02-01', 'expense', 500, 'Mobile topup'],
    ['2025-02-03', 'income', 2000, 'Cash deposit'],
    ['2025-02-04', 'expense', 25, 'NPR fee'],
  ]);
});

Deno.test('PDF: an amount with no direction takes it from the balance', () => {
  const y = (n: number) => 100 + n * 20;
  const row = (n: number, d: string, t: string, a: string, b: string) => [
    left(d, 30, y(n)),
    left(t, 120, y(n)),
    right(a, 400, y(n)),
    right(b, 560, y(n)),
  ];
  const head = [
    left('Date', 30, 100),
    left('Remarks', 120, 100),
    right('Amount', 400, 100),
    right('Balance', 560, 100),
  ];
  const parsed = parseStatementPdf([[
    ...head,
    ...row(1, '2025-02-01', 'Opening Balance', '', '5,000.00'),
    ...row(2, '2025-02-02', 'Tea shop', '120.00', '4,880.00'),
    ...row(3, '2025-02-03', 'Refund', '300.00', '5,180.00'),
    ...row(4, '2025-02-04', 'Bus fare', '80.00', '5,100.00'),
    ...row(5, '2025-02-05', 'Rent', '4,000.00', '1,100.00'),
  ]]);
  assertEquals(brief(parsed.entries), [
    ['2025-02-02', 'expense', 120, 'Tea shop'],
    ['2025-02-03', 'income', 300, 'Refund'],
    ['2025-02-04', 'expense', 80, 'Bus fare'],
    ['2025-02-05', 'expense', 4000, 'Rent'],
  ]);

  // Without balances that add up there is nothing to go by: the rows are
  // reported, not guessed.
  const unsure = parseStatementPdf([[
    ...head,
    ...row(1, '2025-02-02', 'Tea shop', '120.00', '900.00'),
    ...row(2, '2025-02-03', 'Refund', '300.00', '77.00'),
    ...row(3, '2025-02-04', 'Bus fare', '80.00', '5.00'),
  ]]);
  assertEquals(unsure.entries, []);
  assertEquals(
    unsure.skipped.map((s) => [s.page, s.reason]),
    [
      [1, 'Cannot tell if this is money in or out'],
      [1, 'Cannot tell if this is money in or out'],
      [1, 'Cannot tell if this is money in or out'],
    ],
  );
});

Deno.test('PDF: a row that contradicts the balance is marked, not hidden', () => {
  const pages = layoutA();
  // The withdrawal is misprinted as 2,500 while the balance drops by 2,000.
  const cell = pages[0].find((i) => i.str === '2,000.00')!;
  cell.str = '2,500.00';
  const parsed = parseStatementPdf(pages);
  assertEquals(parsed.entries.length, 4);
  assertEquals(parsed.entries.map((e) => Boolean(e.check)), [
    true,
    false,
    false,
    false,
  ]);
  // The printed amount is kept exactly as printed.
  assertEquals(parsed.entries[0].amount, 2500);
});

Deno.test('PDF: unreadable rows are reported with their page', () => {
  const y = (n: number) => 100 + n * 20;
  const parsed = parseStatementPdf([[
    left('Date', 30, 100),
    left('Description', 120, 100),
    right('Debit', 400, 100),
    right('Credit', 480, 100),
    left('2025-02-01', 30, y(1)),
    left('Fine', 120, y(1)),
    right('100.00', 400, y(1)),
    left('31/02/2025', 30, y(2)),
    left('No such day', 120, y(2)),
    right('50.00', 400, y(2)),
    left('2025-02-03', 30, y(3)),
    left('Nothing moved', 120, y(3)),
  ]]);
  assertEquals(brief(parsed.entries), [['2025-02-01', 'expense', 100, 'Fine']]);
  assertEquals(parsed.skipped.map((s) => [s.page, s.reason]), [
    [1, 'Date not recognised'],
    [1, 'No amount'],
  ]);
});

// ---------------------------------------------------------------------------
// Nepali variations
// ---------------------------------------------------------------------------
Deno.test('PDF: Bikram Sambat dates are handed over as printed and marked', () => {
  const y = (n: number) => 100 + n * 20;
  const parsed = parseStatementPdf([[
    left('Miti', 30, 100),
    left('Particulars', 120, 100),
    right('Debit', 400, 100),
    right('Credit', 480, 100),
    left('2081-10-05', 30, y(1)),
    left('Khaja', 120, y(1)),
    right('250.00', 400, y(1)),
  ]]);
  assertEquals(parsed.entries.length, 1);
  assertEquals(parsed.entries[0].calendar, 'bs');
  assertEquals(parsed.entries[0].occurred_at, '2081-10-05 00:00:00');

  // When both calendars are printed the AD date is the one read.
  const both = parseStatementPdf([[
    left('Date (BS)', 30, 100),
    left('Date', 110, 100),
    left('Particulars', 190, 100),
    right('Debit', 400, 100),
    right('Credit', 480, 100),
    left('2081-10-05', 30, y(1)),
    left('2025-01-18', 110, y(1)),
    left('Khaja', 190, y(1)),
    right('250.00', 400, y(1)),
  ]]);
  assertEquals(both.entries[0].calendar, undefined);
  assertEquals(both.entries[0].occurred_at, '2025-01-18 00:00:00');
});

Deno.test('PDF: a date and time on the line, in several spellings', () => {
  assertEquals(leadingDate('2025-01-15 10:22:31 ATM'), {
    date: '2025-01-15 10:22:31',
    rest: 'ATM',
  });
  assertEquals(leadingDate('15-Jan-2025'), { date: '15-Jan-2025', rest: '' });
  assertEquals(leadingDate('15/01/25 9:05 PM'), {
    date: '15/01/25 9:05 PM',
    rest: '',
  });
  assertEquals(leadingDate('Jan 15, 2025 rent'), {
    date: 'Jan 15, 2025',
    rest: 'rent',
  });
  assertEquals(leadingDate('FT/2025-01-15'), null);
  assertEquals(leadingDate('1,250.00'), null);
});

Deno.test('PDF: a line drawn as one piece of text is split into its cells', () => {
  const line = (str: string, y: number): TextItem => ({
    str,
    x: 30,
    y,
    width: str.length * W,
  });
  const parsed = parseStatementPdf([[
    line('Date          Description              Debit       Credit      Balance', 100),
    line('2025-03-01    Opening Balance                                  1,000.00', 120),
    line('2025-03-02    Lunch                    300.00                    700.00', 140),
    line('2025-03-03    Transfer in                           500.00     1,200.00', 160),
    line('2025-03-04    Taxi                     150.00                  1,050.00', 180),
  ]]);
  assertEquals(brief(parsed.entries), [
    ['2025-03-02', 'expense', 300, 'Lunch'],
    ['2025-03-03', 'income', 500, 'Transfer in'],
    ['2025-03-04', 'expense', 150, 'Taxi'],
  ]);
  assertEquals(parsed.balanceChecked, true);
  assertEquals(parsed.entries.filter((e) => e.check).length, 0);
});

Deno.test('PDF with no heading row: read only when the balances add up', () => {
  const line = (str: string, y: number): TextItem => ({
    str,
    x: 30,
    y,
    width: str.length * W,
  });
  const parsed = parseStatementPdf([[
    line('Account activity', 60),
    line('01 Mar 2025 Carried over 0.00 1,000.00', 100),
    line('02 Mar 2025 Lunch at cafe 300.00 700.00', 120),
    line('03 Mar 2025 Transfer in 500.00 1,200.00', 140),
    line('04 Mar 2025 Taxi 150.00 1,050.00', 160),
    line('05 Mar 2025 Groceries 450.00 600.00', 180),
  ]]);
  assertEquals(parsed.format, 'lines');
  assertEquals(brief(parsed.entries), [
    ['2025-03-02', 'expense', 300, 'Lunch at cafe'],
    ['2025-03-03', 'income', 500, 'Transfer in'],
    ['2025-03-04', 'expense', 150, 'Taxi'],
    ['2025-03-05', 'expense', 450, 'Groceries'],
  ]);

  const nonsense = parseStatementPdf([[
    line('02 Mar 2025 Lunch at cafe 300.00 9.00', 120),
    line('03 Mar 2025 Transfer in 500.00 44.00', 140),
    line('04 Mar 2025 Taxi 150.00 3.00', 160),
  ]]);
  assertEquals(nonsense.entries, []);
});

Deno.test('a PDF that is not a statement yields nothing', () => {
  const parsed = parseStatementPdf([[
    left('Dear customer,', 40, 60),
    left('Your card will be renewed on 2025-04-01.', 40, 80),
  ]]);
  assertEquals(parsed.entries, []);
  assertEquals(parsed.format, 'none');
  assertEquals(parsed.unreadPages, [1]);
  assertEquals(parseStatementPdf([[]]).unreadPages, []);
});

// ---------------------------------------------------------------------------
// The format registry
// ---------------------------------------------------------------------------
Deno.test('readStatement: names the bank and the reader that understood it', () => {
  const a = readStatement({ kind: 'pdf', pages: layoutA() });
  assertEquals(a.source, 'bank');
  assertEquals(a.format, 'pdf-table');
  assertEquals(a.provider, 'Global IME Bank');
  assertEquals(a.pageCount, 1);
  assertEquals(a.entries.length, 4);

  const b = readStatement({ kind: 'pdf', pages: layoutB() });
  assertEquals(b.provider, 'Nabil Bank');
  assertEquals(b.unreadPages, [3]);
  assertEquals(b.pageCount, 3);

  const nothing = readStatement({
    kind: 'pdf',
    pages: [[left('Hello', 10, 10)]],
  });
  assertEquals(nothing.source, 'unknown');
  assertEquals(nothing.entries, []);
});

Deno.test('readStatement: a wallet is known by its heading or the hint', () => {
  const rows = [
    ['Date', 'Transaction ID', 'Service', 'Amount', 'Type', 'Status'],
    ['2025-03-02 10:15:00', 'KH123', 'Mobile Topup', '100', 'Debit', 'Completed'],
    ['2025-03-03 08:00:00', 'KH124', 'Bank Load', '2000', 'Credit', 'Completed'],
    ['2025-03-04 09:30:00', 'KH125', 'Movie Ticket', '600', 'Debit', 'Failed'],
  ];
  // Said by the user.
  const hinted = readStatement({ kind: 'sheet', rows, hint: 'khalti' });
  assertEquals(hinted.source, 'khalti');
  assertEquals(
    hinted.entries.map((e) => [e.type, e.amount, e.method, e.ref]),
    [
      ['expense', 100, 'khalti', 'KH123'],
      ['income', 2000, 'khalti', 'KH124'],
    ],
  );
  // Said by the file, whatever was picked.
  const named = readStatement({
    kind: 'sheet',
    rows: [['Khalti Transaction History'], ...rows],
    hint: 'bank',
  });
  assertEquals(named.source, 'khalti');
  // A bank statement that merely mentions a wallet in a row stays a bank's.
  const bank = parseSheet([
    ['Date', 'Description', 'Debit', 'Credit'],
    ['2025-03-02', 'KHALTI LOAD', '500', ''],
  ]);
  assertEquals(bank.source, 'bank');
  assertEquals(bank.entries[0].method, undefined);
});

Deno.test('detectProvider: longer names win over the names inside them', () => {
  assertEquals(detectProvider('GLOBAL IME BANK LTD.')?.name, 'Global IME Bank');
  assertEquals(detectProvider('IME Pay wallet statement')?.name, 'IME Pay');
  assertEquals(detectProvider('Statement of account'), null);
});
