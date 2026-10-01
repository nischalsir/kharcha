import { assertEquals } from 'jsr:@std/assert@1';
import {
  detectKind,
  parseBankPages,
  parseEsewaRows,
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
    },
    {
      occurred_at: '2026-09-30 18:12:21',
      description: 'Fund Transferred by A B',
      amount: 1500.5,
      type: 'income',
      method: 'esewa',
    },
  ]);
});

Deno.test('eSewa sheet: an unrelated spreadsheet yields nothing', () => {
  assertEquals(parseEsewaRows([['Name', 'Amount'], ['Rent', '5000']]), []);
  assertEquals(parseEsewaRows([]), []);
});
