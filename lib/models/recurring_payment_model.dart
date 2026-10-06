import 'dart:math' as math;

import '../core/utils/json_parsers.dart';
import '../services/nepali_date_service.dart';
import 'payment_method.dart';
import 'transaction_model.dart';

enum RecurringFrequency {
  daily('daily', 'Daily'),
  weekly('weekly', 'Weekly'),
  monthly('monthly', 'Monthly'),
  yearly('yearly', 'Yearly'),
  custom('custom', 'Custom');

  const RecurringFrequency(this.code, this.label);

  final String code;
  final String label;

  static RecurringFrequency fromCode(String? code) {
    for (final frequency in RecurringFrequency.values) {
      if (frequency.code == code) return frequency;
    }
    return RecurringFrequency.monthly;
  }
}

class RecurringPayment {
  const RecurringPayment({
    required this.id,
    required this.title,
    required this.amount,
    required this.frequency,
    required this.startDate,
    required this.nextDate,
    required this.createdAt,
    required this.updatedAt,
    this.type = TransactionType.expense,
    this.categoryId,
    this.paymentMethod = PaymentMethod.cash,
    this.intervalDays,
    this.anchorBsDay,
    this.endDate,
    this.isActive = true,
    this.notes,
    this.lastPaidAt,
    this.deletedAt,
  });

  final String id;
  final String title;
  final double amount;
  final TransactionType type;
  final String? categoryId;
  final PaymentMethod paymentMethod;
  final RecurringFrequency frequency;
  final int? intervalDays;
  final int? anchorBsDay;
  final DateTime startDate;
  final DateTime nextDate;
  final DateTime? endDate;
  final bool isActive;
  final String? notes;
  final DateTime? lastPaidAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// What this comes to in an average month, whatever it repeats by: a
  /// weekly bill is paid a little more than four times a month, a yearly one
  /// is a twelfth of itself.
  double get monthlyAmount => switch (frequency) {
    RecurringFrequency.daily => amount * 365 / 12,
    RecurringFrequency.weekly => amount * 52 / 12,
    RecurringFrequency.monthly => amount,
    RecurringFrequency.yearly => amount / 12,
    RecurringFrequency.custom =>
      amount * 365 / 12 / math.max(1, intervalDays ?? 1),
  };

  bool isDue(DateTime now) {
    if (!isActive) return false;
    final today = DateTime(now.year, now.month, now.day);
    return !nextDate.isAfter(today);
  }

  DateTime nextAfter(DateTime from, NepaliDateService bs) {
    final base = DateTime(from.year, from.month, from.day);
    switch (frequency) {
      case RecurringFrequency.daily:
        return DateTime(base.year, base.month, base.day + 1);
      case RecurringFrequency.weekly:
        return DateTime(base.year, base.month, base.day + 7);
      case RecurringFrequency.custom:
        final step = math.max(1, intervalDays ?? 1);
        return DateTime(base.year, base.month, base.day + step);
      case RecurringFrequency.monthly:
        final current = bs.toBs(base);
        final next = bs.shiftMonth(BsDate(current.year, current.month, 1), 1);
        final maxDay = bs.daysInMonth(next.year, next.month);
        final day = math.min(anchorBsDay ?? current.day, maxDay);
        return bs.toGregorian(BsDate(next.year, next.month, day));
      case RecurringFrequency.yearly:
        final current = bs.toBs(base);
        final year = current.year + 1;
        final maxDay = bs.daysInMonth(year, current.month);
        final day = math.min(anchorBsDay ?? current.day, maxDay);
        return bs.toGregorian(BsDate(year, current.month, day));
    }
  }

  factory RecurringPayment.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final interval = json['interval_days'];
    final anchor = json['anchor_bs_day'];
    return RecurringPayment(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      amount: jsonDouble(json['amount']),
      type: TransactionType.fromCode(json['type'] as String?),
      categoryId: jsonString(json['category_id']),
      paymentMethod: PaymentMethod.fromCode(json['payment_method'] as String?),
      frequency: RecurringFrequency.fromCode(json['frequency'] as String?),
      intervalDays: interval is num ? interval.toInt() : null,
      anchorBsDay: anchor is num ? anchor.toInt() : null,
      startDate: jsonDate(json['start_date']) ?? now,
      nextDate: jsonDate(json['next_date']) ?? now,
      endDate: jsonDate(json['end_date']),
      isActive: (json['is_active'] as bool?) ?? true,
      notes: jsonString(json['notes']),
      lastPaidAt: jsonDateTime(json['last_paid_at']),
      createdAt: jsonDateTime(json['created_at']) ?? now,
      updatedAt: jsonDateTime(json['updated_at']) ?? now,
      deletedAt: jsonDateTime(json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'amount': amount,
      'type': type == TransactionType.income ? 'income' : 'expense',
      'category_id': categoryId,
      'payment_method': paymentMethod.code,
      'frequency': frequency.code,
      'interval_days': intervalDays,
      'anchor_bs_day': anchorBsDay,
      'start_date': jsonDateString(startDate),
      'next_date': jsonDateString(nextDate),
      'end_date': endDate == null ? null : jsonDateString(endDate!),
      'is_active': isActive,
      'notes': notes,
      'last_paid_at': lastPaidAt == null ? null : jsonTimestamp(lastPaidAt!),
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
      'deleted_at': deletedAt == null ? null : jsonTimestamp(deletedAt!),
    };
  }

  RecurringPayment copyWith({
    String? id,
    String? title,
    double? amount,
    TransactionType? type,
    String? Function()? categoryId,
    PaymentMethod? paymentMethod,
    RecurringFrequency? frequency,
    int? Function()? intervalDays,
    int? Function()? anchorBsDay,
    DateTime? startDate,
    DateTime? nextDate,
    DateTime? Function()? endDate,
    bool? isActive,
    String? Function()? notes,
    DateTime? Function()? lastPaidAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return RecurringPayment(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      categoryId: categoryId != null ? categoryId() : this.categoryId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      frequency: frequency ?? this.frequency,
      intervalDays: intervalDays != null ? intervalDays() : this.intervalDays,
      anchorBsDay: anchorBsDay != null ? anchorBsDay() : this.anchorBsDay,
      startDate: startDate ?? this.startDate,
      nextDate: nextDate ?? this.nextDate,
      endDate: endDate != null ? endDate() : this.endDate,
      isActive: isActive ?? this.isActive,
      notes: notes != null ? notes() : this.notes,
      lastPaidAt: lastPaidAt != null ? lastPaidAt() : this.lastPaidAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }
}
