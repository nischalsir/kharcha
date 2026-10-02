import '../core/utils/json_parsers.dart';

/// A ledger several accounts share: a family's, or flatmates'.
class Household {
  const Household({
    required this.id,
    required this.name,
    required this.inviteCode,
    this.ownerId,
  });

  final String id;
  final String name;

  /// What someone types to join. Anyone who has it can.
  final String inviteCode;
  final String? ownerId;

  factory Household.fromJson(Map<String, dynamic> json) {
    return Household(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      inviteCode: (json['invite_code'] as String?) ?? '',
      ownerId: jsonString(json['owner_id']),
    );
  }
}

class HouseholdMember {
  const HouseholdMember({
    required this.userId,
    required this.householdId,
    required this.displayName,
    this.isOwner = false,
  });

  final String userId;
  final String householdId;
  final String displayName;
  final bool isOwner;

  factory HouseholdMember.fromJson(Map<String, dynamic> json) {
    return HouseholdMember(
      userId: json['user_id'] as String,
      householdId: json['household_id'] as String,
      displayName: (json['display_name'] as String?) ?? '',
      isOwner: json['role'] == 'owner',
    );
  }
}

/// One expense in the shared ledger.
class HouseholdEntry {
  const HouseholdEntry({
    required this.id,
    required this.householdId,
    required this.paidBy,
    required this.title,
    required this.amount,
    required this.occurredAt,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.deletedAt,
  });

  final String id;
  final String householdId;

  /// The member whose money it was.
  final String paidBy;
  final String title;
  final double amount;
  final DateTime occurredAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory HouseholdEntry.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return HouseholdEntry(
      id: json['id'] as String,
      householdId: json['household_id'] as String,
      paidBy: (json['paid_by'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      amount: jsonDouble(json['amount']),
      occurredAt: jsonDateTime(json['occurred_at']) ?? now,
      notes: jsonString(json['notes']),
      createdAt: jsonDateTime(json['created_at']) ?? now,
      updatedAt: jsonDateTime(json['updated_at']) ?? now,
      deletedAt: jsonDateTime(json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'household_id': householdId,
      'paid_by': paidBy,
      'title': title,
      'amount': amount,
      'occurred_at': jsonTimestamp(occurredAt),
      'notes': notes,
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
      'deleted_at': deletedAt == null ? null : jsonTimestamp(deletedAt!),
    };
  }

  HouseholdEntry copyWith({
    String? paidBy,
    String? title,
    double? amount,
    DateTime? occurredAt,
    String? Function()? notes,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return HouseholdEntry(
      id: id,
      householdId: householdId,
      paidBy: paidBy ?? this.paidBy,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      occurredAt: occurredAt ?? this.occurredAt,
      notes: notes != null ? notes() : this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }
}
