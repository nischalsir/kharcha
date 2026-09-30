import '../core/utils/json_parsers.dart';

enum CategoryKind {
  expense('expense'),
  income('income'),
  both('both');

  const CategoryKind(this.code);

  final String code;

  bool get allowsExpense => this != CategoryKind.income;

  bool get allowsIncome => this != CategoryKind.expense;

  static CategoryKind fromCode(String? code) {
    for (final kind in CategoryKind.values) {
      if (kind.code == code) return kind;
    }
    return CategoryKind.expense;
  }
}

class CategoryModel {
  const CategoryModel({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.kind = CategoryKind.expense,
    this.icon = 'category',
    this.colorValue,
    this.isDefault = false,
    this.sortOrder = 0,
    this.deletedAt,
  });

  final String id;
  final String name;
  final CategoryKind kind;
  final String icon;
  final int? colorValue;
  final bool isDefault;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final color = json['color_value'];
    return CategoryModel(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      kind: CategoryKind.fromCode(json['kind'] as String?),
      icon: (json['icon'] as String?) ?? 'category',
      colorValue: color is num ? color.toInt() : null,
      isDefault: (json['is_default'] as bool?) ?? false,
      sortOrder: jsonInt(json['sort_order']),
      createdAt: jsonDateTime(json['created_at']) ?? now,
      updatedAt: jsonDateTime(json['updated_at']) ?? now,
      deletedAt: jsonDateTime(json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'kind': kind.code,
      'icon': icon,
      'color_value': colorValue,
      'is_default': isDefault,
      'sort_order': sortOrder,
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
      'deleted_at': deletedAt == null ? null : jsonTimestamp(deletedAt!),
    };
  }

  CategoryModel copyWith({
    String? name,
    CategoryKind? kind,
    String? icon,
    int? Function()? colorValue,
    bool? isDefault,
    int? sortOrder,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return CategoryModel(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      icon: icon ?? this.icon,
      colorValue: colorValue != null ? colorValue() : this.colorValue,
      isDefault: isDefault ?? this.isDefault,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }
}
