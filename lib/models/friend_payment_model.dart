import '../core/utils/json_parsers.dart';

class FriendPayment {
  const FriendPayment({
    required this.id,
    required this.creditId,
    required this.amount,
    required this.paidAt,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.deletedAt,
  });

  final String id;
  final String creditId;
  final double amount;
  final DateTime paidAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory FriendPayment.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return FriendPayment(
      id: json['id'] as String,
      creditId: json['credit_id'] as String,
      amount: jsonDouble(json['amount']),
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
      'credit_id': creditId,
      'amount': amount,
      'paid_at': jsonTimestamp(paidAt),
      'notes': notes,
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
      'deleted_at': deletedAt == null ? null : jsonTimestamp(deletedAt!),
    };
  }

  FriendPayment copyWith({
    double? amount,
    DateTime? paidAt,
    String? Function()? notes,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return FriendPayment(
      id: id,
      creditId: creditId,
      amount: amount ?? this.amount,
      paidAt: paidAt ?? this.paidAt,
      notes: notes != null ? notes() : this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }
}
