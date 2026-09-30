import '../core/utils/json_parsers.dart';
import 'payment_method.dart';

class PasalPayment {
  const PasalPayment({
    required this.id,
    required this.pasalId,
    required this.creditId,
    required this.amount,
    required this.paidAt,
    required this.createdAt,
    required this.updatedAt,
    this.paymentMethod = PaymentMethod.cash,
    this.notes,
    this.deletedAt,
  });

  final String id;
  final String pasalId;
  final String creditId;
  final double amount;
  final PaymentMethod paymentMethod;
  final DateTime paidAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  factory PasalPayment.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return PasalPayment(
      id: json['id'] as String,
      pasalId: json['pasal_id'] as String,
      creditId: json['credit_id'] as String,
      amount: jsonDouble(json['amount']),
      paymentMethod: PaymentMethod.fromCode(json['payment_method'] as String?),
      paidAt: jsonDateTime(json['paid_at']) ?? now,
      notes: jsonString(json['notes']),
      createdAt: jsonDateTime(json['created_at']) ?? now,
      updatedAt: jsonDateTime(json['updated_at']) ?? now,
      deletedAt: jsonDateTime(json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'pasal_id': pasalId,
      'credit_id': creditId,
      'amount': amount,
      'payment_method': paymentMethod.code,
      'paid_at': jsonTimestamp(paidAt),
      'notes': notes,
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
      'deleted_at': deletedAt == null ? null : jsonTimestamp(deletedAt!),
    };
  }

  PasalPayment copyWith({
    String? id,
    String? pasalId,
    String? creditId,
    double? amount,
    PaymentMethod? paymentMethod,
    DateTime? paidAt,
    String? Function()? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return PasalPayment(
      id: id ?? this.id,
      pasalId: pasalId ?? this.pasalId,
      creditId: creditId ?? this.creditId,
      amount: amount ?? this.amount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paidAt: paidAt ?? this.paidAt,
      notes: notes != null ? notes() : this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }
}
