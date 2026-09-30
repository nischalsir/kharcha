import '../core/utils/json_parsers.dart';

class PasalCreditItem {
  const PasalCreditItem({
    required this.id,
    required this.creditId,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.createdAt,
    required this.updatedAt,
    this.sortOrder = 0,
    this.deletedAt,
  });

  final String id;
  final String creditId;
  final String itemName;
  final double quantity;
  final String unit;
  final double unitPrice;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  double get totalPrice => computeTotal(quantity, unitPrice);

  bool get isDeleted => deletedAt != null;

  static double computeTotal(double quantity, double unitPrice) {
    return roundMoney(quantity * unitPrice);
  }

  factory PasalCreditItem.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return PasalCreditItem(
      id: json['id'] as String,
      creditId: json['credit_id'] as String,
      itemName: (json['item_name'] as String?) ?? '',
      quantity: jsonDouble(json['quantity']),
      unit: (json['unit'] as String?) ?? 'pcs',
      unitPrice: jsonDouble(json['unit_price']),
      sortOrder: jsonInt(json['sort_order']),
      createdAt: jsonDateTime(json['created_at']) ?? now,
      updatedAt: jsonDateTime(json['updated_at']) ?? now,
      deletedAt: jsonDateTime(json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'credit_id': creditId,
      'item_name': itemName,
      'quantity': quantity,
      'unit': unit,
      'unit_price': unitPrice,
      'sort_order': sortOrder,
      'created_at': jsonTimestamp(createdAt),
      'updated_at': jsonTimestamp(updatedAt),
      'deleted_at': deletedAt == null ? null : jsonTimestamp(deletedAt!),
    };
  }

  PasalCreditItem copyWith({
    String? id,
    String? creditId,
    String? itemName,
    double? quantity,
    String? unit,
    double? unitPrice,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return PasalCreditItem(
      id: id ?? this.id,
      creditId: creditId ?? this.creditId,
      itemName: itemName ?? this.itemName,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }
}
