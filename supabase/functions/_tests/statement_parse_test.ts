import { assertEquals } from 'jsr:@std/assert@1';
import {
  detectKind,
  parseBankPages,
  parseEsewaRows,
  parseGenericRows,
  parseMoneyCell,
  parseSheet,
  parseStatementDate,
  type SkippedRow,
  type TextItem,
} from '../_shared/statement_parse.ts';

// Column positions as the bank statement draws them.
const cell = (str: string, x: number, y: number): TextItem => ({
  str,
  x,
  y,
  width: str.length * 6,
});

const heading = (y: number): TextItem[] => [
  cell('Transaction Date', 149, y),
  cell('Description', 305, y),
  cell('Withdraw', 440, y),
  cell('Deposit', 565, y),
  cell('Balance', 688, y),
  cell('S.N', 75, y),
];

Deno.test('detectKind goes by content, not file name', () => {
  assertEquals(detectKind(new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d])), 'pdf');
  assertEquals(detectKind(new Uint8Array([0xd0, 0xcf, 0x11, 0xe0])), 'sheet');
  assertEquals(detectKind(new Uint8Array([0x50, 0x4b, 0x03, 0x04])), 'sheet');
  assertEquals(detectKind(new Uint8Array([1, 2, 3, 4])), 'unknown');
  assertEquals(detectKind(new Uint8Array([])), 'unknown');
});

Deno.test('bank PDF: the column decides withdrawal or deposit', () => {
  const page: TextItem[] = [
    ...heading(310),
    // Opening balance has a date but no time, so it is not a transaction.
    cell('2026-01-01', 164, 334),
    cell('Opening Balance', 289, 334),
    cell('-', 463, 334),
    cell('-', 583, 334),
    cell('360.41', 692, 334),
    // A withdrawal.
    cell('2026-03-01 19:50:58', 139, 354),
    cell('QR-Pay,CMPAY,', 289, 354),
    cell('100.00', 447, 354),
    cell('-', 583, 354),
    cell('138.21', 692, 354),
    cell('1', 82, 354),
    // A deposit, with a thousands separator.
    cell('2026-03-01 11:16:04', 139, 374),
    cell('FT/09620042209/Saman', 269, 374),
    cell('-', 463, 374),
    cell('5,000.00', 562, 374),
    cell('5,013.21', 687, 374),
    cell('6', 82, 374),
  ];

  assertEquals(parseBankPages([page]), [
    {
      occurred_at: '2026-03-01 19:50:58',
      description: 'QR-Pay,CMPAY',
      amount: 100,
      type: 'expense',
    },
    {
      occurred_at: '2026-03-01 11:16:04',
      description: 'FT/09620042209/Saman',
      amount: 5000,
      type: 'income',
    },
  ]);
});

Deno.test('bank PDF: rows are read across pages in any item order', () => {
  const first = heading(310);
  // Second page repeats no heading and lists its cells out of order.
  const second: TextItem[] = [
    cell('938.21', 692, 60),
    cell('65.00', 450, 60),
    cell('ESEWA', 313, 60),
    cell('-', 583, 60),
    cell('2026-02-28 15:08:22', 139, 60),
  ];
  assertEquals(parseBankPages([first, second]), [
    {
      occurred_at: '2026-02-28 15:08:22',
      description: 'ESEWA',
      amount: 65,
      type: 'expense',
    },
  ]);
});

Deno.test('bank PDF: nothing is guessed without the heading row', () => {
  assertEquals(
    parseBankPages([[
      cell('2026-03-01 19:50:58', 139, 354),
      cell('ESEWA', 313, 354),
      cell('100.00', 447, 354),
    ]]),
    [],
  );
});

Deno.test('eSewa sheet: Dr is spending, Cr is income', () => {
  const rows = [
    ['Statement Report'],
    [],
    ['From Date', 'Sun Jul 05 00:00:00 NPT 2026'],
    [
      'Reference Code',
      'Date Time',
      'Description',
      'Dr.',
      'Cr.',
      'Status',
      'Balance (NPR)',
      'Channel',
    ],
    ['1SC0VTI', '2026-09-30 19:11:27.0', 'Paid for MINI MART', '50.0', '0.0', 'COMPLETE', '275.0', 'App'],
    ['1SBQF6A', '2026-09-30 18:12:21.0', 'Fund Transferred by A B', '0.0', '1,500.5', 'COMPLETE', '525.0', 'App'],
    ['1SAAAAA', '2026-09-29 10:00:00.0', 'Paid for CANCELLED', '80.0', '0.0', 'CANCELED', '525.0', 'App'],
    ['', '', 'Total', '130.0', '1500.5', '', '', ''],
    [],
    ['Total', '3'],
  ];

  assertEquals(parseEsewaRows(rows), [
    {
      occurred_at: '2026-09-30 19:11:27',
      description: 'Paid for MINI MART',
      amount: 50,
      type: 'expense',
      method: 'esewa',
      ref: '1SC0VTI',
    },
    {
      occurred_at: '2026-09-30 18:12:21',
      description: 'Fund Transferred by A B',
      amount: 1500.5,
      type: 'income',
      method: 'esewa',
      ref: '1SBQF6A',
    },
  ]);
});

Deno.test('eSewa sheet: an unrelated spreadsheet yields nothing', () => {
  assertEquals(parseEsewaRows([['Name', 'Amount'], ['Rent', '5000']]), []);
  assertEquals(parseEsewaRows([]), []);
});

const csv = (text: string) => new TextEncoder().encode(text);

Deno.test('a CSV file is recognised by being separated text', () => {
  assertEquals(
    detectKind(csv('Date,Description,Debit,Credit\n2026-01-02,Tea,50,\n')),
    'sheet',
  );
  assertEquals(detectKind(csv('just a sentence with no table')), 'unknown');
  // Binary that is not a known format is still unknown.
  assertEquals(
    detectKind(new Uint8Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])),
    'unknown',
  );
});

Deno.test('dates: the formats banks use', () => {
  const stamp = (text: string) => {
    const result = parseStatementDate(text);
    return 'stamp' in result ? result.stamp : result.error;
  };
  assertEquals(stamp('2026-03-01'), '2026-03-01 00:00:00');
  assertEquals(stamp('2026-03-01 19:50:58'), '2026-03-01 19:50:58');
  assertEquals(stamp('01/03/2026'), '2026-03-01 00:00:00');
  assertEquals(stamp('25/12/2026'), '2026-12-25 00:00:00');
  // Only makes sense month-first.
  assertEquals(stamp('12/25/2026'), '2026-12-25 00:00:00');
  assertEquals(stamp('01-Mar-2026'), '2026-03-01 00:00:00');
  assertEquals(stamp('1 March 2026'), '2026-03-01 00:00:00');
  assertEquals(stamp('Mar 1, 2026'), '2026-03-01 00:00:00');
  assertEquals(stamp('01/03/26 02:15 PM'), '2026-03-01 14:15:00');
});

Deno.test('dates: nothing is guessed', () => {
  const error = (text: string) => {
    const result = parseStatementDate(text);
    return 'error' in result ? result.error : 'parsed';
  };
  assertEquals(error(''), 'No date');
  assertEquals(error('yesterday'), 'Date not recognised');
  assertEquals(error('31/02/2026'), 'Date not recognised');
  assertEquals(error('2026-13-01'), 'Date not recognised');
  // A Bikram Sambat date must not be read as the year 2083 AD.
  assertEquals(error('2083-06-15'), 'Bikram Sambat date');
});

Deno.test('money cells: separators, currency, brackets and Dr/Cr', () => {
  assertEquals(parseMoneyCell('1,250.00'), { amount: 1250, sign: 0 });
  assertEquals(parseMoneyCell('Rs. 500'), { amount: 500, sign: 0 });
  assertEquals(parseMoneyCell('NPR 75.50'), { amount: 75.5, sign: 0 });
  assertEquals(parseMoneyCell('(75.00)'), { amount: 75, sign: -1 });
  assertEquals(parseMoneyCell('-75'), { amount: 75, sign: -1 });
  assertEquals(parseMoneyCell('120.00 Dr'), { amount: 120, sign: -1 });
  assertEquals(parseMoneyCell('120.00 CR'), { amount: 120, sign: 1 });
  assertEquals(parseMoneyCell('-'), { amount: 0, sign: 0 });
  assertEquals(parseMoneyCell(''), { amount: 0, sign: 0 });
  assertEquals(parseMoneyCell('n/a'), null);
  assertEquals(parseMoneyCell('12.3.4'), null);
});

Deno.test('generic bank sheet: debit and credit columns, any bank', () => {
  const rows = [
    ['Some Bank Ltd'],
    ['Account statement', '', '', ''],
    [],
    ['Txn Date', 'Particulars', 'Withdrawal', 'Deposit', 'Balance', 'Ref No'],
    ['01/03/2026', 'Opening Balance', '', '', '1,000.00', ''],
    ['02/03/2026', 'ATM cash', '500.00', '', '500.00', 'A1'],
    ['03/03/2026', 'Salary', '', '25,000.00', '25,500.00', 'A2'],
    ['', 'Total', '500.00', '25,000.00', '', ''],
  ];
  assertEquals(parseGenericRows(rows), [
    {
      occurred_at: '2026-03-02 00:00:00',
      description: 'ATM cash',
      amount: 500,
      type: 'expense',
      ref: 'A1',
    },
    {
      occurred_at: '2026-03-03 00:00:00',
      description: 'Salary',
      amount: 25000,
      type: 'income',
      ref: 'A2',
    },
  ]);
});

Deno.test('generic bank sheet: one amount column with a type or a sign', () => {
  const typed = [
    ['Date', 'Narration', 'Amount', 'Dr/Cr'],
    ['2026-03-02', 'Groceries', '1,200.00', 'DR'],
    ['2026-03-03', 'Refund', '300.00', 'CR'],
  ];
  assertEquals(parseGenericRows(typed).map((e) => [e.type, e.amount]), [
    ['expense', 1200],
    ['income', 300],
  ]);

  const signed = [
    ['Date', 'Description', 'Amount'],
    ['2026-03-02', 'Groceries', '-1200'],
    ['2026-03-03', 'Refund', '+300'],
  ];
  assertEquals(parseGenericRows(signed).map((e) => [e.type, e.amount]), [
    ['expense', 1200],
    ['income', 300],
  ]);
});

Deno.test('generic bank sheet: unreadable rows are reported, not invented', () => {
  const skipped: SkippedRow[] = [];
  const rows = [
    ['Date', 'Description', 'Debit', 'Credit'],
    ['2026-03-02', 'Tea', '50', ''],
    ['sometime', 'Mystery', '70', ''],
    ['2026-03-04', 'Broken amount', 'abc', ''],
    ['2083-06-15', 'BS dated', '90', ''],
    ['2026-03-05', 'Nothing moved', '', ''],
  ];
  const entries = parseGenericRows(rows, skipped);
  assertEquals(entries.length, 1);
  assertEquals(skipped.map((s) => [s.row, s.reason]), [
    [3, 'Date not recognised'],
    [4, 'Amount not recognised'],
    [5, 'Bikram Sambat date'],
    [6, 'No amount'],
  ]);
});

Deno.test('generic bank sheet: an amount with no direction is not guessed', () => {
  const skipped: SkippedRow[] = [];
  const entries = parseGenericRows([
    ['Date', 'Description', 'Amount'],
    ['2026-03-02', 'In or out?', '500'],
  ], skipped);
  assertEquals(entries, []);
  assertEquals(skipped[0].reason, 'Cannot tell if this is money in or out');
});

Deno.test('a sheet with no transaction table yields nothing', () => {
  assertEquals(parseGenericRows([['Name', 'Phone'], ['Ram', '98']]), []);
  assertEquals(parseSheet([['Name', 'Phone'], ['Ram', '98']]).source, 'unknown');
});

Deno.test('parseSheet tells eSewa from a bank export', () => {
  const esewa = parseSheet([
    ['Reference Code', 'Date Time', 'Description', 'Dr.', 'Cr.', 'Status'],
    ['R1', '2026-09-30 19:11:27.0', 'Paid for X', '50.0', '0.0', 'COMPLETE'],
    ['R2', '2026-09-30 19:12:00.0', '', '50.0', '0.0', 'COMPLETE'],
  ]);
  assertEquals(esewa.source, 'esewa');
  assertEquals(esewa.entries.length, 1);
  assertEquals(esewa.entries[0].ref, 'R1');
  assertEquals(esewa.skipped.map((s) => [s.row, s.reason]), [
    [3, 'No description'],
  ]);

  const bank = parseSheet([
    ['Date', 'Description', 'Debit', 'Credit'],
    ['2026-03-02', 'Tea', '50', ''],
  ]);
  assertEquals(bank.source, 'bank');
  assertEquals(bank.entries[0].method, undefined);
});
