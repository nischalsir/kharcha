class CurrencyFormatter {
  const CurrencyFormatter._();

  /// Symbol used when a caller does not pass an explicit [symbol]. It is set
  /// from the saved app settings so the whole UI follows the chosen currency.
  static String _symbol = 'NPR';

  static String get symbol => _symbol;

  static void setSymbol(String value) {
    if (value.trim().isNotEmpty) _symbol = value.trim();
  }

  static String _group(String digits) {
    if (digits.length <= 3) return digits;
    final lastThree = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$lastThree';
  }

  static String number(double value, {int decimals = 0}) {
    final fixed = value.abs().toStringAsFixed(decimals);
    final split = fixed.split('.');
    final whole = _group(split[0]);
    final fraction = split.length > 1 ? '.${split[1]}' : '';
    final isZero = double.parse(fixed) == 0;
    final sign = value < 0 && !isZero ? '-' : '';
    return '$sign$whole$fraction';
  }

  /// Money is always written with its paisa, `NPR 1,000.00`, so an amount
  /// reads the same everywhere and a figure like 100.25 is never rounded
  /// away on screen.
  static String format(double value, {String? symbol, int decimals = 2}) {
    final text = number(value.abs(), decimals: decimals);
    final isZero = double.parse(value.abs().toStringAsFixed(decimals)) == 0;
    final sign = value < 0 && !isZero ? '-' : '';
    return '$sign${symbol ?? _symbol} $text';
  }

  static String compact(double value, {String? symbol}) {
    final abs = value.abs();
    final sign = value < 0 ? '-' : '';
    final unit = symbol ?? _symbol;
    if (abs >= 10000000) {
      return '$sign$unit ${(abs / 10000000).toStringAsFixed(2)} Cr';
    }
    if (abs >= 100000) {
      return '$sign$unit ${(abs / 100000).toStringAsFixed(2)} L';
    }
    if (abs >= 1000) {
      return '$sign$unit ${(abs / 1000).toStringAsFixed(1)}K';
    }
    return '$sign$unit ${abs.toStringAsFixed(0)}';
  }
}
