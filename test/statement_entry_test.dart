import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/models/payment_method.dart';
import 'package:kharcha_app/models/statement_entry.dart';
import 'package:kharcha_app/models/transaction_model.dart';

void main() {
  test('an eSewa statement row is an eSewa payment whatever it says', () {
    final entry = StatementEntry.fromJson(<String, dynamic>{
      'occurred_at': '2026-09-30 19:11:27',
      'description': 'Paid for MAHALAXMI MINI MART',
      'amount': 50,
      'type': 'expense',
      'method': 'esewa',
    });

    expect(entry.paymentMethod, PaymentMethod.esewa);
    expect(entry.type, TransactionType.expense);
    expect(entry.amount, 50);
    expect(entry.title, 'Paid for MAHALAXMI MINI MART');
    expect(entry.occurredAt, DateTime(2026, 9, 30, 19, 11, 27));
  });

  test('a bank statement row takes its method from the description', () {
    StatementEntry row(String description) =>
        StatementEntry.fromJson(<String, dynamic>{
          'occurred_at': '2026-03-01 11:16:04',
          'description': description,
          'amount': 5000,
          'type': 'income',
        });

    expect(row('QR-Pay,CMPAY').paymentMethod, PaymentMethod.qr);
    expect(row('ESEWA').paymentMethod, PaymentMethod.esewa);
    expect(row('Khalti LTRF').paymentMethod, PaymentMethod.khalti);
    expect(row('FT/09620042209/Saman').paymentMethod, PaymentMethod.bank);
    expect(row('IBFT/171249739/GRDBL').paymentMethod, PaymentMethod.bank);
    expect(row('FT/09620042209/Saman').isIncome, isTrue);
  });
}
