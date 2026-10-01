/// Evaluates a plain arithmetic expression: numbers with `+ - × ÷` (also
/// accepted as `* /`), with the usual precedence. Returns null when the
/// expression is incomplete or not arithmetic, or when it divides by zero.
///
/// Pure, so the calculator sheet and its tests share one definition.
double? evaluateExpression(String input) {
  final expr = input
      .replaceAll('×', '*')
      .replaceAll('÷', '/')
      .replaceAll('−', '-')
      .replaceAll(',', '')
      .replaceAll(' ', '');
  if (expr.isEmpty) return null;

  final values = <double>[];
  final ops = <String>[];

  bool apply() {
    if (values.length < 2 || ops.isEmpty) return false;
    final b = values.removeLast();
    final a = values.removeLast();
    switch (ops.removeLast()) {
      case '+':
        values.add(a + b);
      case '-':
        values.add(a - b);
      case '*':
        values.add(a * b);
      case '/':
        if (b == 0) return false;
        values.add(a / b);
      default:
        return false;
    }
    return true;
  }

  int precedence(String op) => (op == '+' || op == '-') ? 1 : 2;

  var i = 0;
  var expectNumber = true;
  while (i < expr.length) {
    final char = expr[i];
    if (expectNumber) {
      // A sign is part of the number only where a number is expected.
      final start = i;
      if (char == '-' || char == '+') i++;
      var digits = 0;
      var dots = 0;
      while (i < expr.length) {
        final c = expr.codeUnitAt(i);
        if (c >= 0x30 && c <= 0x39) {
          digits++;
        } else if (expr[i] == '.') {
          dots++;
        } else {
          break;
        }
        i++;
      }
      if (digits == 0 || dots > 1) return null;
      final value = double.tryParse(expr.substring(start, i));
      if (value == null) return null;
      values.add(value);
      expectNumber = false;
      continue;
    }
    if (!'+-*/'.contains(char)) return null;
    while (ops.isNotEmpty && precedence(ops.last) >= precedence(char)) {
      if (!apply()) return null;
    }
    ops.add(char);
    expectNumber = true;
    i++;
  }
  // Ended on an operator: "100 +" is not finished.
  if (expectNumber) return null;
  while (ops.isNotEmpty) {
    if (!apply()) return null;
  }
  final result = values.length == 1 ? values.single : null;
  if (result == null || !result.isFinite) return null;
  return result;
}

/// A result as it should appear in an amount field: whole numbers without a
/// decimal point, everything else rounded to paisa.
String formatCalculatorResult(double value) {
  final rounded = (value * 100).round() / 100;
  if (rounded == rounded.roundToDouble()) return rounded.toStringAsFixed(0);
  return rounded.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}
