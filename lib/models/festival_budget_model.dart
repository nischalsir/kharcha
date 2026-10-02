import '../core/utils/json_parsers.dart';

/// A spending limit for one festival in one BS year.
///
/// The budget carries its own date window rather than looking the festival up
/// each time: what counts is everything spent from [startDate] to [endDate],
/// both included. That keeps a budget meaningful in a year the bundled
/// calendar has no festival dates for, and lets the window be widened for the
/// shopping that happens well before the day itself.
class FestivalBudget {
  const FestivalBudget({
    required this.id,
    required this.festivalId,
    required this.festivalName,
    required this.bsYear,
    required this.amount,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;

  /// The festival's id in the calendar, the same every year it comes round.
  final String festivalId;

  /// The festival's English name when the budget was made, so the budget can
  /// still be named in a year the calendar does not cover.
  final String festivalName;
  final int bsYear;
  final double amount;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// The first moment after the window, for half-open comparisons.
  DateTime get endExclusive =>
      DateTime(endDate.year, endDate.month, endDate.day + 1);

  /// Whether [day] falls inside the window.
  bool covers(DateTime day) =>
      !day.isBefore(startDate) && day.isBefore(endExclusive);

  factory FestivalBudget.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return FestivalBudget(
      id: json['id'] as String,
      festivalId: (json['festival_id'] as String?) ?? '',
      festivalName: (json['festival_name'] as String?) ?? '',
      bsYear: jsonInt(json['bs_year']),
      amount: jsonDouble(json['amount']),
      startDate: jsonDate(json['start_date']) ?? today,
      endDate: jsonDate(json['end_date']) ?? today,
      createdAt: jsonDateTime(json['created_at']) ?? now,
      updatedAt: jsonDateTime(json['updated_at']) ?? now,
      deletedAt: jsonDateTime(json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'festival_id': festivalId,
      'festival_name': festivalName,
      'bs_year': bsYear,
      'amount': amount,
      'start_date': jsonDateString(startDate),
      'end_date': jsonDateString(endDate),
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
      'deleted_at': deletedAt == null ? null : jsonTimestamp(deletedAt!),
    };
  }

  FestivalBudget copyWith({
    double? amount,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return FestivalBudget(
      id: id,
      festivalId: festivalId,
      festivalName: festivalName,
      bsYear: bsYear,
      amount: amount ?? this.amount,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }
}
