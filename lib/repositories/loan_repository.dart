import '../core/errors/app_failure.dart';
import '../core/utils/id_generator.dart';
import '../models/loan_model.dart';
import '../models/payment_method.dart';
import '../models/recurring_payment_model.dart';
import '../models/sync_models.dart';
import '../models/transaction_model.dart';
import 'cached_repository.dart';
import 'recurring_payment_repository.dart';
import 'transaction_repository.dart';

class LoanRepository extends CachedRepository<Loan> {
  LoanRepository(super.cache, super.sync, this._recurring, this._transactions);

  /// Longest name the backend accepts (`char_length(name) <= 80`).
  static const int maxNameLength = 80;
  static const int maxMonths = 600;

  final RecurringPaymentRepository _recurring;
  final TransactionRepository _transactions;

  @override
  SyncEntity get entity => SyncEntity.loans;

  @override
  Loan parse(Map<String, dynamic> json) => Loan.fromJson(json);

  @override
  Map<String, dynamic> serialize(Loan item) => item.toJson();

  List<Loan> all() {
    final list = readAll()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  Loan? byId(String id) {
    final row = cache.row(entity, id);
    return row == null ? null : Loan.fromJson(row);
  }

  /// How many instalments have been paid: those from before the loan was
  /// added, plus one for every payment recorded against its reminder since.
  /// Capped at the tenure, so an extra tap cannot overpay the loan.
  int paidCount(Loan loan) {
    var count = loan.paidBefore;
    final recurringId = loan.recurringId;
    if (recurringId != null) {
      for (final item in _transactions.all()) {
        if (item.recurringId == recurringId && item.isCompleted) count++;
      }
    }
    return count > loan.tenureMonths ? loan.tenureMonths : count;
  }

  /// The reminder that goes with the loan, if it still exists.
  RecurringPayment? reminderFor(Loan loan) {
    final id = loan.recurringId;
    return id == null ? null : _recurring.byId(id);
  }

  /// Adds a loan and the monthly payment that reminds about its instalments.
  Future<Loan> create({
    required String name,
    required double principal,
    required double annualRate,
    required int tenureMonths,
    required DateTime firstDueDate,
    double? emiAmount,
    String? lender,
    int paidBefore = 0,
    PaymentMethod paymentMethod = PaymentMethod.bank,
    String? notes,
  }) async {
    final title = name.trim();
    if (title.isEmpty) {
      throw const AppFailure(FailureKind.invalidData, 'Name is required.');
    }
    if (title.length > maxNameLength) {
      throw const AppFailure(FailureKind.invalidData, 'Name is too long.');
    }
    if (principal <= 0) {
      throw const AppFailure(
        FailureKind.invalidData,
        'The amount borrowed must be greater than zero.',
      );
    }
    if (annualRate < 0 || annualRate > 100) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Interest must be between 0 and 100 percent.',
      );
    }
    if (tenureMonths < 1 || tenureMonths > maxMonths) {
      throw const AppFailure(
        FailureKind.invalidData,
        'The loan must run for 1 to 600 months.',
      );
    }
    if (paidBefore < 0 || paidBefore >= tenureMonths) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Instalments already paid must be fewer than the months of the loan.',
      );
    }
    final emi =
        emiAmount ??
        emiFor(
          principal: principal,
          annualRate: annualRate,
          months: tenureMonths,
        );
    if (emi <= 0) {
      throw const AppFailure(
        FailureKind.invalidData,
        'The instalment must be greater than zero.',
      );
    }

    final now = DateTime.now();
    final day = DateTime(
      firstDueDate.year,
      firstDueDate.month,
      firstDueDate.day,
    );
    final reminder = await _recurring.create(
      title: '$title EMI',
      amount: emi,
      frequency: RecurringFrequency.monthly,
      startDate: day,
      template: RecurringPayment(
        id: '',
        title: '$title EMI',
        amount: emi,
        frequency: RecurringFrequency.monthly,
        startDate: day,
        nextDate: day,
        createdAt: now,
        updatedAt: now,
        type: TransactionType.expense,
        paymentMethod: paymentMethod,
      ),
    );
    final loan = Loan(
      id: newId(),
      name: title,
      lender: lender,
      principal: principal,
      annualRate: annualRate,
      tenureMonths: tenureMonths,
      emiAmount: emi,
      firstDueDate: day,
      paidBefore: paidBefore,
      recurringId: reminder.id,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    await write(loan);
    return loan;
  }

  /// Records one instalment as paid: an expense is saved and the reminder
  /// moves to next month. Once the last one is paid the reminder stops.
  Future<void> payInstalment(String id) async {
    final loan = byId(id);
    if (loan == null) {
      throw const AppFailure(FailureKind.invalidData, 'Loan not found.');
    }
    if (paidCount(loan) >= loan.tenureMonths) {
      throw const AppFailure(
        FailureKind.invalidData,
        'This loan is already paid off.',
      );
    }
    final reminder = reminderFor(loan);
    if (reminder != null) {
      await _recurring.markPaid(reminder.id);
    } else {
      // The reminder was deleted; the payment is still the loan's.
      await _transactions.create(
        title: '${loan.name} EMI',
        amount: loan.emiAmount,
        type: TransactionType.expense,
        occurredAt: DateTime.now(),
        paymentMethod: PaymentMethod.bank,
        recurringId: loan.recurringId,
      );
    }
    await stopReminderIfPaidOff(id);
  }

  /// Pauses the reminder of a loan whose last instalment has been paid,
  /// however it was paid. Returns whether it had to.
  Future<bool> stopReminderIfPaidOff(String id) async {
    final loan = byId(id);
    if (loan == null) return false;
    final reminder = reminderFor(loan);
    if (reminder == null || !reminder.isActive) return false;
    if (paidCount(loan) < loan.tenureMonths) return false;
    await _recurring.setActive(reminder.id, active: false);
    return true;
  }

  /// Removes the loan and its reminder. Payments already recorded stay.
  Future<void> delete(String id) async {
    final loan = byId(id);
    if (loan == null) return;
    final reminder = reminderFor(loan);
    if (reminder != null) await _recurring.delete(reminder.id);
    final now = DateTime.now();
    await write(loan.copyWith(deletedAt: () => now, updatedAt: now));
  }
}
