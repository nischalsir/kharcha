import '../core/utils/json_parsers.dart';

enum PasalCreditStatus {
  unpaid('unpaid'),
  partiallyPaid('partially_paid'),
  paid('paid'),
  overdue('overdue');

  const PasalCreditStatus(this.dbValue);

  final String dbValue;

  static PasalCreditStatus fromDb(String? value) {
    switch (value) {
      case 'partially_paid':
        return PasalCreditStatus.partiallyPaid;
      case 'paid':
        return PasalCreditStatus.paid;
      default:
        return PasalCreditStatus.unpaid;
    }
  }

  String get label {
    switch (this) {
      case PasalCreditStatus.unpaid:
        return 'Unpaid';
      case PasalCreditStatus.partiallyPaid:
        return 'Partially Paid';
      case PasalCreditStatus.paid:
        return 'Paid';
      case PasalCreditStatus.overdue:
        return 'Overdue';
    }
  }
}

class PasalCredit {
  const PasalCredit({
    required this.id,
    required this.pasalId,
    required this.title,
    required this.purchaseDate,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.dueDate,
    this.totalAmount = 0,
    this.paidAmount = 0,
    this.status = PasalCreditStatus.unpaid,
    this.deletedAt,
  });

  final String id;
  final String pasalId;
  final String title;
  final String? notes;
  final DateTime purchaseDate;
  final DateTime? dueDate;
  final double totalAmount;
  final double paidAmount;
  final PasalCreditStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  double get remainingAmount => roundMoney(totalAmount - paidAmount);

  bool get isDeleted => deletedAt != null;

  bool isOverdue(DateTime now) {
    final due = dueDate;
    if (due == null || remainingAmount <= 0) return false;
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(due.year, due.month, due.day).isBefore(today);
  }

  PasalCreditStatus displayStatus(DateTime now) {
    if (isOverdue(now)) return PasalCreditStatus.overdue;
    if (remainingAmount <= 0 && totalAmount > 0) return PasalCreditStatus.paid;
    if (paidAmount > 0) return PasalCreditStatus.partiallyPaid;
    return PasalCreditStatus.unpaid;
  }

  factory PasalCredit.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return PasalCredit(
      id: json['id'] as String,
      pasalId: json['pasal_id'] as String,
      title: (json['title'] as String?) ?? '',
      notes: jsonString(json['notes']),
      purchaseDate: jsonDate(json['purchase_date']) ?? now,
      dueDate: jsonDate(json['due_date']),
      totalAmount: jsonDouble(json['total_amount']),
      paidAmount: jsonDouble(json['paid_amount']),
      status: PasalCreditStatus.fromDb(json['status'] as String?),
      createdAt: jsonDateTime(json['created_at']) ?? now,
      updatedAt: jsonDateTime(json['updated_at']) ?? now,
      deletedAt: jsonDateTime(json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() {
    final stored = status == PasalCreditStatus.overdue
        ? (paidAmount > 0
              ? PasalCreditStatus.partiallyPaid
              : PasalCreditStatus.unpaid)
        : status;
    return <String, dynamic>{
      'id': id,
      'pasal_id': pasalId,
      'title': title,
      'notes': notes,
      'purchase_date': jsonDateString(purchaseDate),
      'due_date': dueDate == null ? null : jsonDateString(dueDate!),
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'status': stored.dbValue,
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
      'deleted_at': deletedAt == null ? null : jsonTimestamp(deletedAt!),
    };
  }

  PasalCredit copyWith({
    String? id,
    String? pasalId,
    String? title,
    String? Function()? notes,
    DateTime? purchaseDate,
    DateTime? Function()? dueDate,
    double? totalAmount,
    double? paidAmount,
    PasalCreditStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return PasalCredit(
      id: id ?? this.id,
      pasalId: pasalId ?? this.pasalId,
      title: title ?? this.title,
      notes: notes != null ? notes() : this.notes,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      dueDate: dueDate != null ? dueDate() : this.dueDate,
      totalAmount: totalAmount ?? this.totalAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }
}
