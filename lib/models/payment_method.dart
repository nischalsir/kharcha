import '../core/utils/json_parsers.dart';

enum PaymentMethod {
  cash('cash', 'Cash'),
  bank('bank', 'Bank'),
  esewa('esewa', 'eSewa'),
  khalti('khalti', 'Khalti'),
  card('card', 'Card'),
  qr('qr', 'QR'),
  other('other', 'Other');

  const PaymentMethod(this.code, this.label);

  final String code;
  final String label;

  static PaymentMethod fromCode(String? code) {
    for (final method in PaymentMethod.values) {
      if (method.code == code) return method;
    }
    return PaymentMethod.other;
  }
}

class PaymentMethodOption {
  const PaymentMethodOption({
    required this.id,
    required this.method,
    required this.label,
    required this.createdAt,
    required this.updatedAt,
    this.isEnabled = true,
    this.sortOrder = 0,
    this.deletedAt,
  });

  final String id;
  final PaymentMethod method;
  final String label;
  final bool isEnabled;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory PaymentMethodOption.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return PaymentMethodOption(
      id: json['id'] as String,
      method: PaymentMethod.fromCode(json['code'] as String?),
      label: (json['label'] as String?) ?? '',
      isEnabled: (json['is_enabled'] as bool?) ?? true,
      sortOrder: jsonInt(json['sort_order']),
      createdAt: jsonDateTime(json['created_at']) ?? now,
      updatedAt: jsonDateTime(json['updated_at']) ?? now,
      deletedAt: jsonDateTime(json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'code': method.code,
      'label': label,
      'is_enabled': isEnabled,
      'sort_order': sortOrder,
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
      'deleted_at': deletedAt == null ? null : jsonTimestamp(deletedAt!),
    };
  }

  PaymentMethodOption copyWith({
    String? label,
    bool? isEnabled,
    int? sortOrder,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return PaymentMethodOption(
      id: id,
      method: method,
      label: label ?? this.label,
      isEnabled: isEnabled ?? this.isEnabled,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }
}
