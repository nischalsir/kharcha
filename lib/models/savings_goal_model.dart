import '../core/utils/json_parsers.dart';

/// Money being put aside towards something: "Dashain fund, Rs 20,000 by
/// Ashwin". Setting money aside is not spending, so a goal never appears in
/// the expense totals.
class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.createdAt,
    required this.updatedAt,
    this.savedAmount = 0,
    this.targetDate,
    this.notes,
    this.deletedAt,
  });

  final String id;
  final String name;
  final double targetAmount;
  final double savedAmount;

  /// The day the money is wanted by, or null for "whenever".
  final DateTime? targetDate;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  double get remaining {
    final left = roundMoney(targetAmount - savedAmount);
    return left < 0 ? 0 : left;
  }

  double get fraction => targetAmount <= 0 ? 0 : savedAmount / targetAmount;

  int get percent => (fraction * 100).floor().clamp(0, 999);

  bool get isReached => savedAmount >= targetAmount;

  /// Whole days from [now] until [targetDate]; negative once it has passed.
  /// Null when the goal has no date.
  int? daysLeft(DateTime now) {
    final due = targetDate;
    if (due == null) return null;
    return DateTime(
      due.year,
      due.month,
      due.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  /// What has to be put aside each month from [now] to arrive on time, or
  /// null when there is no date, the date has passed or the goal is reached.
  double? monthlyNeeded(DateTime now) {
    final days = daysLeft(now);
    if (days == null || days <= 0 || isReached) return null;
    // A date under a month away still needs the whole remainder.
    final months = days / 30;
    return roundMoney(months <= 1 ? remaining : remaining / months);
  }

  factory SavingsGoal.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return SavingsGoal(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      targetAmount: jsonDouble(json['target_amount']),
      savedAmount: jsonDouble(json['saved_amount']),
      targetDate: jsonDate(json['target_date']),
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
      'target_amount': targetAmount,
      'saved_amount': savedAmount,
      'target_date': targetDate == null ? null : jsonDateString(targetDate!),
      'notes': notes,
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
      'deleted_at': deletedAt == null ? null : jsonTimestamp(deletedAt!),
    };
  }

  SavingsGoal copyWith({
    String? name,
    double? targetAmount,
    double? savedAmount,
    DateTime? Function()? targetDate,
    String? Function()? notes,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return SavingsGoal(
      id: id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      savedAmount: savedAmount ?? this.savedAmount,
      targetDate: targetDate != null ? targetDate() : this.targetDate,
      notes: notes != null ? notes() : this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }
}
