/// Phone numbers as people type them and as contacts store them.
///
/// A number arrives in many shapes: `9812345678`, `+977 981-2345678`,
/// `00977 9812345678`, `+977+9812345678`, `(01) 4-123456`, or with Nepali
/// digits. It is kept in one: an optional `+` and then digits only.
class PhoneNumber {
  const PhoneNumber._();

  /// The longest number the field accepts while typing, spaces and all.
  static const int maxInputLength = 24;

  /// The fewest and most digits a real number has: a short landline, and
  /// the international limit.
  static const int minDigits = 6;
  static const int maxDigits = 15;

  static const String _nepaliDigits = '०१२३४५६७८९';

  /// [raw] tidied into `+9779812345678` or `9812345678`. Null when nothing
  /// was typed.
  ///
  /// Only a `+` at the very start counts; one typed again after the country
  /// code (`+977+98…`) is dropped. `00` at the start is the same as `+`.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;

    final digits = StringBuffer();
    var plus = false;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final nepali = _nepaliDigits.indexOf(char);
      if (nepali >= 0) {
        digits.write(nepali);
      } else if (rune >= 0x30 && rune <= 0x39) {
        digits.write(char);
      } else if (char == '+' && digits.isEmpty) {
        plus = true;
      }
      // Spaces, dashes, brackets, dots and a second `+` are only spacing.
    }
    var number = digits.toString();
    if (number.isEmpty) return null;
    if (!plus && number.startsWith('00') && number.length > minDigits + 2) {
      plus = true;
      number = number.substring(2);
    }
    return plus ? '+$number' : number;
  }

  /// Whether [normalized] (as [normalize] returns it) has a believable
  /// number of digits.
  static bool isValid(String normalized) {
    final digits = normalized.startsWith('+')
        ? normalized.substring(1)
        : normalized;
    return digits.length >= minDigits &&
        digits.length <= maxDigits &&
        RegExp(r'^\d+$').hasMatch(digits);
  }
}
