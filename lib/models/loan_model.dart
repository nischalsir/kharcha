import 'dart:math' as math;

import '../core/utils/json_parsers.dart';

/// The equal monthly instalment that repays [principal] over [months] at
/// [annualRate] percent a year, on a reducing balance. With no interest it is
/// simply the principal divided by the months.
double emiFor({
  required double principal,
  required double annualRate,
  required int months,
}) {
  if (principal <= 0 || months <= 0) return 0;
  final rate = annualRate / 1200;
  if (rate <= 0) return roundMoney(principal / months);
  final growth = math.pow(1 + rate, months);
  return roundMoney(principal * rate * growth / (growth - 1));
}

/// A loan being repaid in equal monthly instalments (EMI).
class Loan {
  const Loan({
    required this.id,
    required this.name,
    required this.principal,
    required this.annualRate,
    required this.tenureMonths,
    required this.emiAmount,
    required this.firstDueDate,
    required this.createdAt,
    required this.updatedAt,
    this.lender,
    this.paidBefore = 0,
    this.recurringId,
    this.notes,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String? lender;
  final double principal;

  /// Interest per year, in percent.
  final double annualRate;
  final int tenureMonths;

  /// What is paid each month. Normally [emiFor], but the bank's own figure
  /// can be entered when it differs by a few rupees.
  final double emiAmount;
  final DateTime firstDueDate;

  /// Instalments already paid before the loan was added to the app.
  final int paidBefore;

  /// The recurring payment that reminds about, and records, the instalments.
  final String? recurringId;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  double get _rate => annualRate / 1200;

  /// Everything that will have been paid by the end.
  double get totalPayable => roundMoney(emiAmount * tenureMonths);

  /// What the loan costs on top of what was borrowed.
  double get totalInterest {
    final interest = roundMoney(totalPayable - principal);
    return interest < 0 ? 0 : interest;
  }

  /// The principal still owed after [paid] instalments.
  double outstandingAfter(int paid) {
    final done = paid.clamp(0, tenureMonths);
    if (done >= tenureMonths) return 0;
    final rate = _rate;
    if (rate <= 0) {
      final left = principal - emiAmount * done;
      return left < 0 ? 0 : roundMoney(left);
    }
    final growth = math.pow(1 + rate, done);
    final left = principal * growth - emiAmount * (growth - 1) / rate;
    return left < 0 ? 0 : roundMoney(left);
  }

  /// The part of instalment number [number] (1-based) that is interest.
  double interestIn(int number) =>
      roundMoney(outstandingAfter(number - 1) * _rate);

  factory Loan.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return Loan(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      lender: jsonString(json['lender']),
      principal: jsonDouble(json['principal']),
      annualRate: jsonDouble(json['annual_rate']),
      tenureMonths: jsonInt(json['tenure_months'], fallback: 1),
      emiAmount: jsonDouble(json['emi_amount']),
      firstDueDate:
          jsonDate(json['first_due_date']) ??
          DateTime(now.year, now.month, now.day),
      paidBefore: jsonInt(json['paid_before']),
      recurringId: jsonString(json['recurring_id']),
      notes: jsonString(json['notes']),
      createdAt: jsonDateTime(json['created_at']) ?? now,
      updatedAt: jsonDateTime(json['updated_at']) ?? now,
      deletedAt: jsonDateTime(json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'lender': lender,
      'principal': principal,
      'annual_rate': annualRate,
      'tenure_months': tenureMonths,
      'emi_amount': emiAmount,
      'first_due_date': jsonDateString(firstDueDate),
      'paid_before': paidBefore,
      'recurring_id': recurringId,
      'notes': notes,
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
      'deleted_at': deletedAt == null ? null : jsonTimestamp(deletedAt!),
    };
  }

  Loan copyWith({
    String? name,
    String? Function()? lender,
    String? Function()? recurringId,
    String? Function()? notes,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return Loan(
      id: id,
      name: name ?? this.name,
      lender: lender != null ? lender() : this.lender,
      principal: principal,
      annualRate: annualRate,
      tenureMonths: tenureMonths,
      emiAmount: emiAmount,
      firstDueDate: firstDueDate,
      paidBefore: paidBefore,
      recurringId: recurringId != null ? recurringId() : this.recurringId,
      notes: notes != null ? notes() : this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }
}
