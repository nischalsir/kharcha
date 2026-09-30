import '../core/utils/json_parsers.dart';
import 'payment_method.dart';

enum TransactionType {
  expense('expense', 'Expense'),
  income('income', 'Income'),
  transfer('transfer', 'Transfer');

  const TransactionType(this.code, this.label);

  final String code;
  final String label;

  static TransactionType fromCode(String? code) {
    for (final type in TransactionType.values) {
      if (type.code == code) return type;
    }
    return TransactionType.expense;
  }
}

enum TransactionStatus {
  completed('completed', 'Completed'),
  pending('pending', 'Pending');

  const TransactionStatus(this.code, this.label);

  final String code;
  final String label;

  static TransactionStatus fromCode(String? code) {
    return code == 'pending'
        ? TransactionStatus.pending
        : TransactionStatus.completed;
  }
}

class TransactionModel {
  const TransactionModel({
    required this.id,
    required this.title,
    required this.amount,
    required this.type,
    required this.occurredAt,
    required this.createdAt,
    required this.updatedAt,
    this.status = TransactionStatus.completed,
    this.categoryId,
    this.paymentMethod = PaymentMethod.cash,
    this.notes,
    this.attachmentPath,
    this.recurringId,
    this.deletedAt,
  });

  final String id;
  final String title;
  final double amount;
  final TransactionType type;
  final TransactionStatus status;
  final String? categoryId;
  final PaymentMethod paymentMethod;
  final DateTime occurredAt;
  final String? notes;
  final String? attachmentPath;
  final String? recurringId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isExpense => type == TransactionType.expense;

  bool get isIncome => type == TransactionType.income;

  bool get isCompleted => status == TransactionStatus.completed;

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return TransactionModel(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      amount: jsonDouble(json['amount']),
      type: TransactionType.fromCode(json['type'] as String?),
      status: TransactionStatus.fromCode(json['status'] as String?),
      categoryId: jsonString(json['category_id']),
      paymentMethod: PaymentMethod.fromCode(json['payment_method'] as String?),
      occurredAt: jsonDateTime(json['occurred_at']) ?? now,
      notes: jsonString(json['notes']),
      attachmentPath: jsonString(json['attachment_path']),
      recurringId: jsonString(json['recurring_id']),
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
      'type': type.code,
      'status': status.code,
      'category_id': categoryId,
      'payment_method': paymentMethod.code,
      'occurred_at': jsonTimestamp(occurredAt),
      'notes': notes,
      'attachment_path': attachmentPath,
      'recurring_id': recurringId,
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
      'deleted_at': deletedAt == null ? null : jsonTimestamp(deletedAt!),
    };
  }

  TransactionModel copyWith({
    String? id,
    String? title,
    double? amount,
    TransactionType? type,
    TransactionStatus? status,
    String? Function()? categoryId,
    PaymentMethod? paymentMethod,
    DateTime? occurredAt,
    String? Function()? notes,
    String? Function()? attachmentPath,
    String? Function()? recurringId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      status: status ?? this.status,
      categoryId: categoryId != null ? categoryId() : this.categoryId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      occurredAt: occurredAt ?? this.occurredAt,
      notes: notes != null ? notes() : this.notes,
      attachmentPath: attachmentPath != null
          ? attachmentPath()
          : this.attachmentPath,
      recurringId: recurringId != null ? recurringId() : this.recurringId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }
}
