import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/constants/categories.dart';
import 'package:kharcha_app/core/errors/app_failure.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/core/utils/currency_formatter.dart';
import 'package:kharcha_app/models/loan_model.dart';
import 'package:kharcha_app/models/payment_method.dart';
import 'package:kharcha_app/models/statement_entry.dart';
import 'package:kharcha_app/models/sync_models.dart';
import 'package:kharcha_app/models/transaction_model.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:kharcha_app/providers/household_provider.dart';
import 'package:kharcha_app/providers/loan_provider.dart';
import 'package:kharcha_app/providers/transaction_provider.dart';
import 'package:kharcha_app/repositories/household_repository.dart';
import 'package:kharcha_app/repositories/loan_repository.dart';
import 'package:kharcha_app/repositories/recurring_payment_repository.dart';
import 'package:kharcha_app/repositories/settings_repository.dart';
import 'package:kharcha_app/repositories/transaction_repository.dart';
import 'package:kharcha_app/screens/household/household_screen.dart';
import 'package:kharcha_app/screens/loans/loans_screen.dart';
import 'package:kharcha_app/screens/payments/sms_import_screen.dart';
import 'package:kharcha_app/services/backup_service.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/sms_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _mockConnectivity() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => <String>['wifi'],
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    (call) async => null,
  );
}

class _Env {
  _Env(this.cache, this.sync)
    : dates = NepaliDateService(),
      settings = SettingsRepository(cache, sync),
      transactions = TransactionRepository(cache, sync),
      household = HouseholdRepository(cache, sync) {
    recurring = RecurringPaymentRepository(cache, sync, transactions, dates);
    loans = LoanRepository(cache, sync, recurring, transactions);
  }

  final CacheService cache;
  final SyncService sync;
  final NepaliDateService dates;
  final SettingsRepository settings;
  final TransactionRepository transactions;
  final HouseholdRepository household;
  late final RecurringPaymentRepository recurring;
  late final LoanRepository loans;

  static Future<_Env> create() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final cache = await CacheService.create();
    return _Env(cache, SyncService(cache: cache, remote: SupabaseService()));
  }

  /// A household of two as the server would hand it over, with this phone's
  /// account being `me`.
  Future<void> seedHousehold() async {
    await sync.adoptUser('me');
    await cache.replaceRows(SyncEntity.households, <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'h1',
        'name': 'Our home',
        'owner_id': 'me',
        'invite_code': 'AB12CD34EF',
      },
    ]);
    await cache.replaceRows(SyncEntity.householdMembers, <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'm1',
        'household_id': 'h1',
        'user_id': 'me',
        'display_name': 'Nischal',
        'role': 'owner',
      },
      <String, dynamic>{
        'id': 'm2',
        'household_id': 'h1',
        'user_id': 'mum',
        'display_name': 'Aama',
        'role': 'member',
      },
    ]);
  }
}

SmsMessage _sms(String body, {String sender = 'LAXMI_ALERT', int id = 1}) {
  return SmsMessage(
    id: id,
    sender: sender,
    body: body,
    date: DateTime(2026, 9, 25, 14, 30, id),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(_mockConnectivity);

  test('money is written with its paisa', () {
    CurrencyFormatter.setSymbol('NPR');
    expect(CurrencyFormatter.format(1000), 'NPR 1,000.00');
    expect(CurrencyFormatter.format(100.25), 'NPR 100.25');
    expect(CurrencyFormatter.format(-1234567.5), '-NPR 12,34,567.50');
    expect(CurrencyFormatter.format(0), 'NPR 0.00');
  });

  group('reading payment alerts from messages', () {
    test('a bank credit, as the bank writes it', () {
      final entry = SmsParser.parse(
        _sms(
          'Dear Customer, Your #20042209 has been credited by NPR 20,000.00 '
          'on 25/09/26. Remarks:FT/09620042209/Ghar bada\n-Laxmi Sunrise',
        ),
      )!;
      expect(entry.type, TransactionType.income);
      expect(entry.amount, 20000);
      expect(entry.title, 'FT/09620042209/Ghar bada');
      expect(entry.paymentMethod, PaymentMethod.bank);
      expect(entry.source, StatementSource.bank);
      expect(entry.occurredAt, DateTime(2026, 9, 25, 14, 30, 1));
    });

    test('a bank debit, as the bank writes it', () {
      final entry = SmsParser.parse(
        _sms(
          'Dear Customer, Your #20042209 has been debited by NPR 10,538.00 '
          'on 25/09/26. Remarks:CIPS//ACCOUNTFT:Nischal Pandey/Done\n'
          '-Laxmi Sunrise',
        ),
      )!;
      expect(entry.type, TransactionType.expense);
      expect(entry.amount, 10538);
      expect(entry.title, 'CIPS//ACCOUNTFT:Nischal Pandey/Done');
      expect(entry.paymentMethod, PaymentMethod.bank);
    });

    test('the balance in a message is not the amount that moved', () {
      final entry = SmsParser.parse(
        _sms(
          'Your A/C XX1234 has been debited by NPR 2,000.00 for QR payment '
          'at ABC Store. Avl Bal NPR 12,345.67',
          sender: 'NICASIA',
        ),
      )!;
      expect(entry.amount, 2000);
      expect(entry.type, TransactionType.expense);
      expect(entry.paymentMethod, PaymentMethod.qr);
      expect(entry.title, 'ABC Store');
    });

    test('a wallet alert is a wallet payment, with its reference', () {
      final paid = SmsParser.parse(
        _sms(
          'You have paid Rs. 500 to NTC Topup. Txn ID: 0ABC12F. Thank you '
          'for using eSewa.',
          sender: 'eSewa',
        ),
      )!;
      expect(paid.type, TransactionType.expense);
      expect(paid.amount, 500);
      expect(paid.paymentMethod, PaymentMethod.esewa);
      expect(paid.source, StatementSource.esewa);
      expect(paid.reference, '0ABC12F');
      expect(paid.title, 'NTC Topup');

      final received = SmsParser.parse(
        _sms('Rs 1,000 received from Ram Bahadur on Khalti.', sender: 'Khalti'),
      )!;
      expect(received.type, TransactionType.income);
      expect(received.paymentMethod, PaymentMethod.khalti);
      expect(received.title, 'Ram Bahadur');
    });

    test('a message that only mentions money is not a transaction', () {
      for (final message in <SmsMessage>[
        _sms('Your OTP for the payment of NPR 500 is 123456. Do not share.'),
        _sms('Your EMI of NPR 5,000 will be debited on 01/10/26.'),
        _sms('Payment of NPR 900 failed. No amount was debited.'),
        _sms('Get cashback up to Rs 200 when you pay with our card!'),
        _sms('Your balance is NPR 4,500.00.'),
        _sms('Hello, how are you?'),
        // A friend's own number, however it is worded.
        _sms(
          'I have paid Rs 500 to the shop for you',
          sender: '+9779812345678',
        ),
      ]) {
        expect(SmsParser.parse(message), isNull, reason: message.body);
      }
    });

    test('a following word is not taken for a reference', () {
      final entry = SmsParser.parse(
        _sms('NPR 750.00 debited and transferred to Sita Sharma.'),
      )!;
      expect(entry.reference, isNull);
      expect(entry.title, 'Sita Sharma');
    });

    test('the same message is the same row every time it is read', () {
      final messages = <SmsMessage>[
        _sms('Your account is credited by NPR 100.00. Remarks:Salary', id: 2),
        _sms('Your account is debited by NPR 40.00. Remarks:Tea', id: 1),
        _sms('Your OTP is 1234', id: 3),
      ];
      final first = SmsParser.parseAll(messages);
      final second = SmsParser.parseAll(messages.reversed.toList());
      expect(first.entries, hasLength(2));
      // Oldest first, like a statement.
      expect(first.entries.map((e) => e.title), <String>['Tea', 'Salary']);
      expect(
        first.entries.map((e) => e.importId),
        second.entries.map((e) => e.importId),
      );
      expect(first.entries.first.importId, isNot(first.entries.last.importId));
    });

    test('the day a message names is read, and odd ones are left alone', () {
      final now = DateTime(2026, 10, 2);
      expect(
        SmsParser.dateIn('credited by NPR 20,000.00 on 25/09/26.', now: now),
        DateTime(2026, 9, 25),
      );
      expect(
        SmsParser.dateIn('debited on 2026-09-30 for QR', now: now),
        DateTime(2026, 9, 30),
      );
      // A Bikram Sambat date, a day that does not exist, one in the future,
      // and an amount that only looks like a date.
      expect(SmsParser.dateIn('on 2083/06/09', now: now), isNull);
      expect(SmsParser.dateIn('on 31/06/26', now: now), isNull);
      expect(SmsParser.dateIn('on 25/12/26', now: now), isNull);
      expect(SmsParser.dateIn('NPR 20,000.00 credited', now: now), isNull);
    });

    test('messages pasted in by hand are read one per paragraph', () {
      final now = DateTime(2026, 10, 2, 9);
      final messages = SmsParser.fromPasted(
        'Dear Customer, Your #20042209 has been credited by NPR 20,000.00 '
        'on 25/09/26. Remarks:FT/09620042209/Ghar bada\n-Laxmi Sunrise\n'
        '\n  \n'
        'Dear Customer, Your #20042209 has been debited by NPR 10,538.00 '
        'on 25/09/26. Remarks:CIPS//ACCOUNTFT:Nischal Pandey/Done\r\n'
        '-Laxmi Sunrise\n\n'
        'Your OTP is 123456\n\n\n',
        now: now,
      );
      expect(messages, hasLength(3));
      // Dated by the day the message names, or today when it names none.
      expect(messages[0].date, DateTime(2026, 9, 25));
      expect(messages[2].date, now);

      final result = SmsParser.parseAll(messages);
      expect(result.entries, hasLength(2));
      expect(result.entries.map((e) => '${e.type.name} ${e.amount}'), <String>[
        'income 20000.0',
        'expense 10538.0',
      ]);
      expect(result.entries.first.title, 'FT/09620042209/Ghar bada');
      expect(SmsParser.fromPasted('   \n\n '), isEmpty);
    });

    test('messages arrive from the phone as they are', () {
      expect(SmsMessage.fromMap(null), isNull);
      expect(SmsMessage.fromMap(<String, Object?>{'body': 'x'}), isNull);
      final message = SmsMessage.fromMap(<String, Object?>{
        'id': 7,
        'sender': 'eSewa',
        'body': 'hi',
        'date': DateTime(2026, 1, 2).millisecondsSinceEpoch,
      })!;
      expect(message.id, 7);
      expect(message.date, DateTime(2026, 1, 2));
    });
  });

  group('loans', () {
    test('the instalment for a loan with and without interest', () {
      expect(emiFor(principal: 120000, annualRate: 0, months: 12), 10000);
      // The textbook figure for 100,000 at 12% over a year.
      expect(emiFor(principal: 100000, annualRate: 12, months: 12), 8884.88);
      expect(emiFor(principal: 0, annualRate: 12, months: 12), 0);
    });

    test('what is owed falls to nothing by the last instalment', () {
      final now = DateTime(2026, 10, 1);
      final loan = Loan(
        id: 'l',
        name: 'Bike',
        principal: 100000,
        annualRate: 12,
        tenureMonths: 12,
        emiAmount: 8884.88,
        firstDueDate: now,
        createdAt: now,
        updatedAt: now,
      );
      expect(loan.outstandingAfter(0), 100000);
      expect(loan.outstandingAfter(1), closeTo(92115.12, 0.01));
      expect(loan.outstandingAfter(12), 0);
      expect(loan.outstandingAfter(40), 0);
      expect(loan.interestIn(1), 1000);
      expect(loan.totalInterest, closeTo(6618.56, 0.01));
      expect(Loan.fromJson(loan.toJson()).emiAmount, loan.emiAmount);
    });

    test(
      'a loan comes with a monthly reminder, and paying moves it on',
      () async {
        final env = await _Env.create();
        addTearDown(env.sync.dispose);
        final loan = await env.loans.create(
          name: 'Bike loan',
          principal: 30000,
          annualRate: 0,
          tenureMonths: 3,
          firstDueDate: DateTime(2026, 10, 1),
          paidBefore: 1,
        );
        final reminder = env.loans.reminderFor(loan)!;
        expect(reminder.title, 'Bike loan EMI');
        expect(reminder.amount, 10000);
        expect(env.loans.paidCount(loan), 1);

        await env.loans.payInstalment(loan.id);
        expect(env.loans.paidCount(loan), 2);
        final payment = env.transactions.all().single;
        expect(payment.amount, 10000);
        expect(payment.type, TransactionType.expense);
        expect(env.loans.reminderFor(loan)!.isActive, isTrue);

        // The last one: the reminder stops, and no fourth can be paid.
        await env.loans.payInstalment(loan.id);
        expect(env.loans.paidCount(loan), 3);
        expect(env.loans.reminderFor(loan)!.isActive, isFalse);
        await expectLater(
          env.loans.payInstalment(loan.id),
          throwsA(isA<AppFailure>()),
        );
        expect(env.transactions.all(), hasLength(2));
      },
    );

    test('paying from the Payments page counts too', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      final loan = await env.loans.create(
        name: 'Phone',
        principal: 20000,
        annualRate: 0,
        tenureMonths: 2,
        firstDueDate: DateTime(2026, 10, 1),
      );
      await env.recurring.markPaid(loan.recurringId!);
      await env.recurring.markPaid(loan.recurringId!);

      final provider = LoanProvider(cache: env.cache, repository: env.loans);
      addTearDown(provider.dispose);
      await Future<void>.delayed(Duration.zero);
      final status = provider.statusOf(loan.id)!;
      expect(status.isPaidOff, isTrue);
      expect(status.outstanding, 0);
      expect(env.loans.reminderFor(loan)!.isActive, isFalse);
    });

    test('a loan that makes no sense is refused', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      Future<Loan> add({
        String name = 'Loan',
        double principal = 1000,
        double rate = 10,
        int months = 12,
        int paid = 0,
      }) => env.loans.create(
        name: name,
        principal: principal,
        annualRate: rate,
        tenureMonths: months,
        firstDueDate: DateTime(2026, 10, 1),
        paidBefore: paid,
      );
      await expectLater(add(name: ' '), throwsA(isA<AppFailure>()));
      await expectLater(add(principal: 0), throwsA(isA<AppFailure>()));
      await expectLater(add(rate: 101), throwsA(isA<AppFailure>()));
      await expectLater(add(months: 0), throwsA(isA<AppFailure>()));
      await expectLater(add(paid: 12), throwsA(isA<AppFailure>()));
      expect(env.loans.all(), isEmpty);
      expect(env.recurring.all(), isEmpty);
    });

    test('deleting a loan removes its reminder, not its payments', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      final loan = await env.loans.create(
        name: 'Phone',
        principal: 20000,
        annualRate: 0,
        tenureMonths: 4,
        firstDueDate: DateTime(2026, 10, 1),
      );
      await env.loans.payInstalment(loan.id);
      await env.loans.delete(loan.id);
      expect(env.loans.all(), isEmpty);
      expect(env.recurring.all(), isEmpty);
      expect(env.transactions.all(), hasLength(1));
    });
  });

  group('household ledger', () {
    test('a shared table is whatever the server shows now', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      await env.seedHousehold();
      final written = await env.household.addEntry(
        title: 'Rice',
        amount: 1800,
        paidBy: 'me',
        occurredAt: DateTime.now(),
      );

      // The server's list: one row from another member, one it has deleted,
      // and not yet the one just written here.
      await env.cache.replaceRows(
        SyncEntity.householdTransactions,
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'theirs',
            'household_id': 'h1',
            'paid_by': 'mum',
            'title': 'Gas',
            'amount': 2000,
            'occurred_at': DateTime.now().toUtc().toIso8601String(),
          },
          <String, dynamic>{
            'id': 'gone',
            'household_id': 'h1',
            'paid_by': 'mum',
            'title': 'Old',
            'amount': 5,
            'occurred_at': DateTime.now().toUtc().toIso8601String(),
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      );
      expect(env.household.entries().map((e) => e.id).toSet(), <String>{
        'theirs',
        written.id,
      });

      // Removed from the household: nothing of it is shown any more.
      await env.cache.clearEntity(SyncEntity.householdTransactions);
      await env.cache.replaceRows(SyncEntity.households, const []);
      expect(env.household.household(), isNull);
      expect(env.household.entries(), isEmpty);
      expect(env.cache.pendingCount, 0);
    });

    test('who paid what this month', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      await env.seedHousehold();
      final now = DateTime.now();
      await env.household.addEntry(
        title: 'Rice',
        amount: 1800,
        paidBy: 'me',
        occurredAt: now,
      );
      await env.household.addEntry(
        title: 'Gas',
        amount: 2000.5,
        paidBy: 'mum',
        occurredAt: now,
      );
      await env.household.addEntry(
        title: 'Milk',
        amount: 200,
        paidBy: 'me',
        occurredAt: now,
      );
      // Last year's is not this month's.
      await env.household.addEntry(
        title: 'Old',
        amount: 999,
        paidBy: 'me',
        occurredAt: DateTime(now.year - 1, now.month, now.day),
      );

      final provider = HouseholdProvider(
        cache: env.cache,
        repository: env.household,
        dates: env.dates,
      );
      addTearDown(provider.dispose);
      expect(provider.household!.name, 'Our home');
      expect(provider.isOwner, isTrue);
      expect(provider.monthTotal, 4000.5);
      expect(
        provider.monthShares.map((s) => '${s.member.displayName}:${s.paid}'),
        <String>['Aama:2000.5', 'Nischal:2000.0'],
      );
      expect(provider.nameOf('mum'), 'Aama');
      expect(provider.nameOf('left'), isNull);

      final milk = provider.monthEntries.firstWhere((e) => e.title == 'Milk');
      expect(await provider.deleteEntry(milk.id), isTrue);
      expect(provider.monthTotal, 3800.5);
    });

    test('an entry needs a title, an amount and a payer', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      // No household yet.
      expect(
        () => env.household.addEntry(
          title: 'Rice',
          amount: 10,
          paidBy: 'me',
          occurredAt: DateTime.now(),
        ),
        throwsA(isA<AppFailure>()),
      );
      await env.seedHousehold();
      Future<void> add(String title, double amount, String payer) =>
          env.household.addEntry(
            title: title,
            amount: amount,
            paidBy: payer,
            occurredAt: DateTime.now(),
          );
      await expectLater(add(' ', 10, 'me'), throwsA(isA<AppFailure>()));
      await expectLater(add('Rice', 0, 'me'), throwsA(isA<AppFailure>()));
      await expectLater(add('Rice', 10, ''), throwsA(isA<AppFailure>()));
      expect(env.household.entries(), isEmpty);
    });

    test('creating and joining need the server', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      await expectLater(
        env.household.create(name: 'Home', displayName: 'Me'),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        env.household.join(code: ' ', displayName: 'Me'),
        throwsA(isA<AppFailure>()),
      );
    });

    test(
      'the household tables are never uploaded or backed up whole',
      () async {
        final env = await _Env.create();
        addTearDown(env.sync.dispose);
        await env.seedHousehold();
        expect(SyncEntity.households.readOnly, isTrue);
        expect(SyncEntity.householdMembers.readOnly, isTrue);
        expect(SyncEntity.householdTransactions.shared, isTrue);
        expect(SyncEntity.loans.shared, isFalse);

        final backup = BackupService(cache: env.cache, sync: env.sync);
        final tables =
            (jsonDecode(backup.exportToJson())
                    as Map<String, dynamic>)['tables']
                as Map<String, dynamic>;
        expect(tables.containsKey('loans'), isTrue);
        expect(tables.containsKey('households'), isFalse);
        expect(tables.containsKey('household_transactions'), isFalse);
      },
    );
  });

  group('built-in categories belong to the account', () {
    test('two accounts never get the same id, one account always does', () {
      final a = SettingsRepository.categoryId('food', 'alice');
      expect(a, SettingsRepository.categoryId('food', 'alice'));
      expect(a, isNot(SettingsRepository.categoryId('food', 'bob')));
      expect(a, isNot(SettingsRepository.categoryId('food', null)));
      expect(
        SettingsRepository.paymentMethodId('cash', 'alice'),
        isNot(SettingsRepository.paymentMethodId('cash', 'bob')),
      );
    });

    test(
      'rows the server kept refusing are moved to ids of their own',
      () async {
        final env = await _Env.create();
        addTearDown(env.sync.dispose);
        // Seeded before anyone signed in: the old shared ids, never uploaded.
        await env.settings.ensureDefaults();
        final legacyFood = SettingsRepository.categoryId('food', null);
        expect(env.cache.row(SyncEntity.categories, legacyFood), isNotNull);
        await env.transactions.create(
          title: 'Momo',
          amount: 250,
          type: TransactionType.expense,
          occurredAt: DateTime.now(),
          categoryId: legacyFood,
        );
        await env.sync.adoptUser('bob');

        final moved = await env.settings.claimDefaultIds('bob');
        expect(moved, greaterThan(0));

        final ownFood = SettingsRepository.categoryId('food', 'bob');
        expect(env.cache.rawRow(SyncEntity.categories, legacyFood), isNull);
        expect(
          env.cache.hasPending(SyncEntity.categories, legacyFood),
          isFalse,
        );
        expect(env.cache.row(SyncEntity.categories, ownFood)!['name'], 'Food');
        expect(env.cache.hasPending(SyncEntity.categories, ownFood), isTrue);
        expect(env.transactions.all().single.categoryId, ownFood);
        expect(
          env.settings.categories(),
          hasLength(DefaultCategories.all.length),
        );
        // Payment methods the same: one row per method, under its own id.
        expect(
          env.settings.paymentMethods(),
          hasLength(PaymentMethod.values.length),
        );
        expect(
          env.cache.row(
            SyncEntity.paymentMethods,
            SettingsRepository.paymentMethodId('cash', 'bob'),
          ),
          isNotNull,
        );
        expect(
          env.cache.rawRow(
            SyncEntity.paymentMethods,
            SettingsRepository.paymentMethodId('cash', null),
          ),
          isNull,
        );

        // Nothing left to do the second time.
        expect(await env.settings.claimDefaultIds('bob'), 0);
      },
    );

    test('the account that did upload the shared rows retires them', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      await env.sync.adoptUser('alice');
      final legacyFood = SettingsRepository.categoryId('food', null);
      final legacyCash = SettingsRepository.paymentMethodId('cash', null);
      // As pulled from the server: Alice's own rows, under the shared ids.
      await env.cache.mergeRemoteRows(
        SyncEntity.categories,
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': legacyFood,
            'user_id': 'alice',
            'name': 'Khana',
            'kind': 'expense',
            'updated_at': '2026-01-01T00:00:00Z',
          },
        ],
      );
      await env.cache.mergeRemoteRows(
        SyncEntity.paymentMethods,
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': legacyCash,
            'user_id': 'alice',
            'code': 'cash',
            'label': 'Cash',
            'updated_at': '2026-01-01T00:00:00Z',
          },
        ],
      );

      await env.settings.claimDefaultIds('alice');

      // The renamed category keeps its name under the new id, and the old
      // row is deleted on the server rather than dropped from the phone.
      final ownFood = SettingsRepository.categoryId('food', 'alice');
      expect(env.cache.row(SyncEntity.categories, ownFood)!['name'], 'Khana');
      final retired = env.cache.rawRow(SyncEntity.categories, legacyFood)!;
      expect(retired['deleted_at'], isNotNull);
      expect(env.cache.hasPending(SyncEntity.categories, legacyFood), isTrue);
      // The server allows one row per method, so that one stays as it is.
      expect(env.cache.row(SyncEntity.paymentMethods, legacyCash), isNotNull);
      expect(
        env.cache.hasPending(SyncEntity.paymentMethods, legacyCash),
        isFalse,
      );
    });

    test('a signed-in account seeds its own ids from the start', () async {
      final env = await _Env.create();
      addTearDown(env.sync.dispose);
      await env.sync.adoptUser('carol');
      await env.settings.ensureDefaults();
      expect(
        env.cache.row(
          SyncEntity.categories,
          SettingsRepository.categoryId('food', 'carol'),
        ),
        isNotNull,
      );
      expect(await env.settings.claimDefaultIds('carol'), 0);
    });
  });

  group('screens', () {
    Future<_Env> env(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      late _Env created;
      await tester.runAsync(() async => created = await _Env.create());
      addTearDown(created.sync.dispose);
      return created;
    }

    Future<void> show(
      WidgetTester tester,
      _Env env,
      Widget home,
      List<InheritedProvider<dynamic>> providers,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: <InheritedProvider<dynamic>>[
            Provider<NepaliDateService>.value(value: env.dates),
            Provider<CacheService>.value(value: env.cache),
            ChangeNotifierProvider<SyncService>.value(value: env.sync),
            ...providers,
          ],
          child: MaterialApp(theme: AppTheme.light(), home: home),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
    }

    testWidgets('Loans shows what is owed and takes an instalment', (
      tester,
    ) async {
      final e = await env(tester);
      await tester.runAsync(
        () => e.loans.create(
          name: 'Bike loan',
          lender: 'Laxmi Sunrise',
          principal: 30000,
          annualRate: 0,
          tenureMonths: 3,
          firstDueDate: DateTime.now().add(const Duration(days: 5)),
        ),
      );
      final provider = LoanProvider(cache: e.cache, repository: e.loans);
      await show(tester, e, const LoansScreen(), <InheritedProvider<dynamic>>[
        ChangeNotifierProvider<LoanProvider>.value(value: provider),
      ]);
      expect(find.text('Bike loan'), findsOneWidget);
      expect(find.text('Laxmi Sunrise'), findsOneWidget);
      expect(find.text('NPR 30,000.00'), findsOneWidget);
      expect(find.textContaining('0 of 3 paid'), findsOneWidget);

      await tester.tap(find.text('Bike loan'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('loan-pay')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1 of 3 paid'), findsOneWidget);
      expect(e.transactions.all().single.amount, 10000);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Household invites to start one, then shows the ledger', (
      tester,
    ) async {
      final e = await env(tester);
      final provider = HouseholdProvider(
        cache: e.cache,
        repository: e.household,
        dates: e.dates,
      );
      await show(
        tester,
        e,
        const HouseholdScreen(),
        <InheritedProvider<dynamic>>[
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
          ChangeNotifierProvider<HouseholdProvider>.value(value: provider),
        ],
      );
      expect(find.text('Start a household'), findsOneWidget);
      expect(find.text('Join with a code'), findsOneWidget);

      await tester.runAsync(() async {
        await e.seedHousehold();
        await e.household.addEntry(
          title: 'Rice',
          amount: 1800,
          paidBy: 'mum',
          occurredAt: DateTime.now(),
        );
      });
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Our home'), findsOneWidget);
      expect(find.text('Rice'), findsOneWidget);
      expect(find.text('Nischal (you)'), findsOneWidget);
      // The total, Aama's share and the entry itself.
      expect(find.text('NPR 1,800.00'), findsNWidgets(3));

      await tester.tap(find.byKey(const ValueKey<String>('household-members')));
      await tester.pumpAndSettle();
      expect(find.text('AB12CD34EF'), findsOneWidget);
      expect(find.text('Leave household'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Import from SMS reviews what it found before saving', (
      tester,
    ) async {
      final e = await env(tester);
      const channel = MethodChannel('test/sms');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'read') {
              return <Object?>[
                <String, Object?>{
                  'id': 1,
                  'sender': 'LAXMI_ALERT',
                  'body':
                      'Dear Customer, Your #20042209 has been debited by NPR '
                      '10,538.00 on 25/09/26. Remarks:CIPS//Done\n'
                      '-Laxmi Sunrise',
                  'date': DateTime.now().millisecondsSinceEpoch,
                },
                <String, Object?>{
                  'id': 2,
                  'sender': 'LAXMI_ALERT',
                  'body': 'Your OTP is 445566',
                  'date': DateTime.now().millisecondsSinceEpoch,
                },
              ];
            }
            return true;
          });
      final transactions = TransactionProvider(
        cache: e.cache,
        repository: e.transactions,
      );
      await show(
        tester,
        e,
        SmsImportScreen(service: SmsService(channel: channel)),
        <InheritedProvider<dynamic>>[
          ChangeNotifierProvider<TransactionProvider>.value(
            value: transactions,
          ),
        ],
      );
      await tester.tap(find.byKey(const ValueKey<String>('sms-scan')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      // The review page, with the one payment and not the OTP.
      expect(find.text('Import statement'), findsOneWidget);
      expect(find.text('CIPS//Done'), findsOneWidget);
      expect(find.text('Import 1'), findsOneWidget);
      // Nothing is saved until it is confirmed.
      expect(e.transactions.all(), isEmpty);

      await tester.tap(find.text('Import 1'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      final saved = e.transactions.all().single;
      expect(saved.amount, 10538);
      expect(saved.type, TransactionType.expense);
      expect(saved.paymentMethod, PaymentMethod.bank);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a refused permission is explained, not ignored', (
      tester,
    ) async {
      final e = await env(tester);
      const channel = MethodChannel('test/sms_refused');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => false);
      await show(
        tester,
        e,
        SmsImportScreen(service: SmsService(channel: channel)),
        const <InheritedProvider<dynamic>>[],
      );
      await tester.tap(find.byKey(const ValueKey<String>('sms-scan')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      // What happened, the steps to allow it, and the way there.
      expect(find.text('Android blocked the SMS permission'), findsOneWidget);
      expect(find.textContaining('Allow restricted settings'), findsWidgets);
      expect(
        find.byKey(const ValueKey<String>('sms-open-settings')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('pasting a message works without any permission', (
      tester,
    ) async {
      final e = await env(tester);
      const channel = MethodChannel('test/sms_none');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return false;
          });
      final transactions = TransactionProvider(
        cache: e.cache,
        repository: e.transactions,
      );
      await show(
        tester,
        e,
        SmsImportScreen(service: SmsService(channel: channel)),
        <InheritedProvider<dynamic>>[
          ChangeNotifierProvider<TransactionProvider>.value(
            value: transactions,
          ),
        ],
      );
      await tester.tap(find.byKey(const ValueKey<String>('sms-paste')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('sms-paste-field')),
        'Dear Customer, Your #20042209 has been debited by NPR 10,538.00 '
        'on 25/09/26. Remarks:CIPS//Done\n-Laxmi Sunrise',
      );
      await tester.tap(find.byKey(const ValueKey<String>('sms-paste-read')));
      await tester.pumpAndSettle();

      // Straight to the review, and the phone was never asked for anything.
      expect(find.text('CIPS//Done'), findsOneWidget);
      expect(find.text('Import 1'), findsOneWidget);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
