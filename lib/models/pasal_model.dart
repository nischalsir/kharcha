import '../core/utils/json_parsers.dart';

class Pasal {
  const Pasal({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.ownerName,
    this.phone,
    this.address,
    this.notes,
    this.logoPath,
    this.isActive = true,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String? ownerName;
  final String? phone;
  final String? address;
  final String? notes;
  final String? logoPath;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  factory Pasal.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return Pasal(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      ownerName: jsonString(json['owner_name']),
      phone: jsonString(json['phone']),
      address: jsonString(json['address']),
      notes: jsonString(json['notes']),
      logoPath: jsonString(json['logo_path']),
      isActive: (json['is_active'] as bool?) ?? true,
      createdAt: jsonDateTime(json['created_at']) ?? now,
      updatedAt: jsonDateTime(json['updated_at']) ?? now,
      deletedAt: jsonDateTime(json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'owner_name': ownerName,
      'phone': phone,
      'address': address,
      'notes': notes,
      'logo_path': logoPath,
      'is_active': isActive,
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
      'deleted_at': deletedAt == null ? null : jsonTimestamp(deletedAt!),
    };
  }

  Pasal copyWith({
    String? id,
    String? name,
    String? Function()? ownerName,
    String? Function()? phone,
    String? Function()? address,
    String? Function()? notes,
    String? Function()? logoPath,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return Pasal(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerName: ownerName != null ? ownerName() : this.ownerName,
      phone: phone != null ? phone() : this.phone,
      address: address != null ? address() : this.address,
      notes: notes != null ? notes() : this.notes,
      logoPath: logoPath != null ? logoPath() : this.logoPath,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }
}
