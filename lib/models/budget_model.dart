import '../core/utils/json_parsers.dart';

enum BudgetPeriod {
  monthly('monthly'),
  weekly('weekly');

  const BudgetPeriod(this.code);

  final String code;

  static BudgetPeriod fromCode(String? code) {
    return code == 'weekly' ? BudgetPeriod.weekly : BudgetPeriod.monthly;
  }
}

enum BudgetLevel { safe, warning, critical, exceeded }

class Budget {
  const Budget({
    required this.id,
    required this.amount,
    required this.bsYear,
    required this.bsMonth,
    required this.createdAt,
    required this.updatedAt,
    this.categoryId,
    this.period = BudgetPeriod.monthly,
    this.weekStart,
    this.deletedAt,
  });

  final String id;
  final String? categoryId;
  final BudgetPeriod period;
  final double amount;
  final int bsYear;
  final int bsMonth;
  final DateTime? weekStart;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory Budget.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return Budget(
      id: json['id'] as String,
      categoryId: jsonString(json['category_id']),
      period: BudgetPeriod.fromCode(json['period'] as String?),
      amount: jsonDouble(json['amount']),
      bsYear: jsonInt(json['bs_year']),
      bsMonth: jsonInt(json['bs_month'], fallback: 1),
      weekStart: jsonDate(json['week_start']),
      createdAt: jsonDateTime(json['created_at']) ?? now,
      updatedAt: jsonDateTime(json['updated_at']) ?? now,
      deletedAt: jsonDateTime(json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'category_id': categoryId,
      'period': period.code,
      'amount': amount,
      'bs_year': bsYear,
      'bs_month': bsMonth,
      'week_start': weekStart == null ? null : jsonDateString(weekStart!),
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
      'deleted_at': deletedAt == null ? null : jsonTimestamp(deletedAt!),
    };
  }

  Budget copyWith({
    String? id,
    String? Function()? categoryId,
    BudgetPeriod? period,
    double? amount,
    int? bsYear,
    int? bsMonth,
    DateTime? Function()? weekStart,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return Budget(
      id: id ?? this.id,
      categoryId: categoryId != null ? categoryId() : this.categoryId,
      period: period ?? this.period,
      amount: amount ?? this.amount,
      bsYear: bsYear ?? this.bsYear,
      bsMonth: bsMonth ?? this.bsMonth,
      weekStart: weekStart != null ? weekStart() : this.weekStart,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }
}

class BudgetProgress {
  const BudgetProgress({required this.budget, required this.spent});

  final Budget budget;
  final double spent;

  double get remaining => roundMoney(budget.amount - spent);

  double get fraction => budget.amount <= 0 ? 0 : spent / budget.amount;

  int get percent => (fraction * 100).round();

  BudgetLevel get level {
    if (fraction >= 1) return BudgetLevel.exceeded;
    if (fraction >= 0.9) return BudgetLevel.critical;
    if (fraction >= 0.8) return BudgetLevel.warning;
    return BudgetLevel.safe;
  }
}
