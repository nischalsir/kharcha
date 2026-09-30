import '../../models/category_model.dart';

class DefaultCategory {
  const DefaultCategory(this.key, this.name, this.kind, this.icon, this.color);

  final String key;
  final String name;
  final CategoryKind kind;
  final String icon;
  final int color;
}

class DefaultCategories {
  const DefaultCategories._();

  static const List<DefaultCategory> all = <DefaultCategory>[
    DefaultCategory(
      'food',
      'Food',
      CategoryKind.expense,
      'restaurant',
      0xFFFF9F0A,
    ),
    DefaultCategory(
      'transport',
      'Transport',
      CategoryKind.expense,
      'directions_bus',
      0xFF0A84FF,
    ),
    DefaultCategory(
      'shopping',
      'Shopping',
      CategoryKind.expense,
      'shopping_bag',
      0xFFBF5AF2,
    ),
    DefaultCategory(
      'bills',
      'Bills',
      CategoryKind.expense,
      'receipt_long',
      0xFFFF453A,
    ),
    DefaultCategory('rent', 'Rent', CategoryKind.expense, 'home', 0xFF64D2FF),
    DefaultCategory(
      'entertainment',
      'Entertainment',
      CategoryKind.expense,
      'movie',
      0xFFFF375F,
    ),
    DefaultCategory(
      'health',
      'Health',
      CategoryKind.expense,
      'favorite',
      0xFF30D158,
    ),
    DefaultCategory(
      'education',
      'Education',
      CategoryKind.expense,
      'school',
      0xFF5E5CE6,
    ),
    DefaultCategory(
      'travel',
      'Travel',
      CategoryKind.expense,
      'flight',
      0xFF32ADE6,
    ),
    DefaultCategory(
      'subscriptions',
      'Subscriptions',
      CategoryKind.expense,
      'subscriptions',
      0xFFAC8E68,
    ),
    DefaultCategory(
      'salary',
      'Salary',
      CategoryKind.income,
      'payments',
      0xFF34C759,
    ),
    DefaultCategory(
      'freelance',
      'Freelance',
      CategoryKind.income,
      'work',
      0xFF00C7BE,
    ),
    DefaultCategory(
      'other',
      'Other',
      CategoryKind.both,
      'category',
      0xFF8E8E93,
    ),
  ];
}
