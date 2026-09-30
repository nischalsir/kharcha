import '../core/utils/json_parsers.dart';

enum FriendCreditDirection {
  iOwe('I_OWE', 'I owe'),
  theyOwe('THEY_OWE', 'They owe me');

  const FriendCreditDirection(this.code, this.label);

  final String code;
  final String label;

  static FriendCreditDirection fromCode(String? code) {
    return code == 'I_OWE'
        ? FriendCreditDirection.iOwe
        : FriendCreditDirection.theyOwe;
  }
}

enum FriendCreditStatus {
  pending('pending', 'Pending'),
  partiallyPaid('partially_paid', 'Partially Paid'),
  paid('paid', 'Paid'),
  overdue('overdue', 'Overdue');

  const FriendCreditStatus(this.code, this.label);

  final String code;
  final String label;

  static FriendCreditStatus fromCode(String? code) {
    switch (code) {
      case 'partially_paid':
        return FriendCreditStatus.partiallyPaid;
      case 'paid':
        return FriendCreditStatus.paid;
      default:
        return FriendCreditStatus.pending;
    }
  }
}

class FriendCredit {
  const FriendCredit({
    required this.id,
    required this.friendId,
    required this.direction,
    required this.title,
    required this.amount,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.paidAmount = 0,
    this.status = FriendCreditStatus.pending,
    this.dueDate,
    this.deletedAt,
  });

  final String id;
  final String friendId;
  final FriendCreditDirection direction;
  final String title;
  final String? notes;
  final double amount;
  final double paidAmount;
  final FriendCreditStatus status;
  final DateTime? dueDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  double get remainingAmount => roundMoney(amount - paidAmount);

  static FriendCreditStatus statusFor(double amount, double paid) {
    if (paid <= 0) return FriendCreditStatus.pending;
    if (paid >= amount) return FriendCreditStatus.paid;
    return FriendCreditStatus.partiallyPaid;
  }

  bool isOverdue(DateTime now) {
    final due = dueDate;
    if (due == null || remainingAmount <= 0) return false;
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(due.year, due.month, due.day).isBefore(today);
  }

  FriendCreditStatus displayStatus(DateTime now) {
    if (isOverdue(now)) return FriendCreditStatus.overdue;
    return statusFor(amount, paidAmount);
  }

  factory FriendCredit.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return FriendCredit(
      id: json['id'] as String,
      friendId: json['friend_id'] as String,
      direction: FriendCreditDirection.fromCode(json['direction'] as String?),
      title: (json['title'] as String?) ?? '',
      notes: jsonString(json['notes']),
      amount: jsonDouble(json['amount']),
      paidAmount: jsonDouble(json['paid_amount']),
      status: FriendCreditStatus.fromCode(json['status'] as String?),
      dueDate: jsonDate(json['due_date']),
      createdAt: jsonDateTime(json['created_at']) ?? now,
      updatedAt: jsonDateTime(json['updated_at']) ?? now,
      deletedAt: jsonDateTime(json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'friend_id': friendId,
      'direction': direction.code,
      'title': title,
      'notes': notes,
      'amount': amount,
      'paid_amount': paidAmount,
      'status': statusFor(amount, paidAmount).code,
      'due_date': dueDate == null ? null : jsonDateString(dueDate!),
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
      'deleted_at': deletedAt == null ? null : jsonTimestamp(deletedAt!),
    };
  }

  FriendCredit copyWith({
    String? friendId,
    FriendCreditDirection? direction,
    String? title,
    String? Function()? notes,
    double? amount,
    double? paidAmount,
    FriendCreditStatus? status,
    DateTime? Function()? dueDate,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return FriendCredit(
      id: id,
      friendId: friendId ?? this.friendId,
      direction: direction ?? this.direction,
      title: title ?? this.title,
      notes: notes != null ? notes() : this.notes,
      amount: amount ?? this.amount,
      paidAmount: paidAmount ?? this.paidAmount,
      status: status ?? this.status,
      dueDate: dueDate != null ? dueDate() : this.dueDate,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }
}
