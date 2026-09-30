import '../core/utils/json_parsers.dart';

class Friend {
  const Friend({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.phone,
    this.avatarPath,
    this.notes,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String? phone;
  final String? avatarPath;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory Friend.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return Friend(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      phone: jsonString(json['phone']),
      avatarPath: jsonString(json['avatar_path']),
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
      'phone': phone,
      'avatar_path': avatarPath,
      'notes': notes,
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
      'deleted_at': deletedAt == null ? null : jsonTimestamp(deletedAt!),
    };
  }

  Friend copyWith({
    String? name,
    String? Function()? phone,
    String? Function()? avatarPath,
    String? Function()? notes,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return Friend(
      id: id,
      name: name ?? this.name,
      phone: phone != null ? phone() : this.phone,
      avatarPath: avatarPath != null ? avatarPath() : this.avatarPath,
      notes: notes != null ? notes() : this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }
}
