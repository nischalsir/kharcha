import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/common/glass_card.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _display = '0';
  String _expression = '';
  double? _lastResult;
  bool _justCalculated = false;

  void _onNumber(String num) {
    setState(() {
      if (_justCalculated || _display == '0') {
        _display = num;
        _justCalculated = false;
      } else {
        _display += num;
      }
      _expression += num;
    });
  }

  void _onOperator(String op) {
    setState(() {
      if (_expression.isEmpty && _display != '0') {
        _expression = _display;
      }
      if (_expression.isNotEmpty &&
          !_isOperator(_expression[_expression.length - 1])) {
        _expression += op;
      } else if (_expression.isNotEmpty) {
        _expression = _expression.substring(0, _expression.length - 1) + op;
      }
      _display = _evaluate(_expression);
      _justCalculated = true;
    });
  }

  void _onEquals() {
    setState(() {
      if (_expression.isNotEmpty) {
        _lastResult = double.tryParse(_evaluate(_expression));
        _display = _lastResult?.toString() ?? 'Error';
        _expression = '';
        _justCalculated = true;
      }
    });
  }

  void _onClear() {
    setState(() {
      _display = '0';
      _expression = '';
      _lastResult = null;
      _justCalculated = false;
    });
  }

  void _onBackspace() {
    setState(() {
      if (_display.length > 1) {
        _display = _display.substring(0, _display.length - 1);
      } else {
        _display = '0';
      }
      if (_expression.isNotEmpty) {
        _expression = _expression.substring(0, _expression.length - 1);
      }
    });
  }

  void _onPercent() {
    setState(() {
      final value = double.tryParse(_display);
      if (value != null) {
        _display = (value / 100).toString();
      }
    });
  }

  void _onSignToggle() {
    setState(() {
      if (!_display.startsWith('-') && _display != '0') {
        _display = '-$_display';
      } else if (_display.startsWith('-')) {
        _display = _display.substring(1);
      }
    });
  }

  bool _isOperator(String char) {
    return char == '+' || char == '-' || char == '×' || char == '÷';
  }

  String _evaluate(String expr) {
    try {
      final sanitized = expr.replaceAll('×', '*').replaceAll('÷', '/');
      final result = _calculate(sanitized);
      if (result == result.roundToDouble()) {
        return result.toInt().toString();
      }
      return result.toStringAsFixed(2);
    } catch (_) {
      return 'Error';
    }
  }

  double _calculate(String expr) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < expr.length; i++) {
      final char = expr[i];
      if (char == '+' || char == '-' || char == '*' || char == '/') {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        tokens.add(char);
      } else {
        buffer.write(char);
      }
    }
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }

    final values = <double>[];
    final ops = <String>[];

    for (final token in tokens) {
      if (token == '+' || token == '-' || token == '*' || token == '/') {
        while (ops.isNotEmpty && _precedence(ops.last) >= _precedence(token)) {
          _applyOp(values, ops.removeLast());
        }
        ops.add(token);
      } else {
        values.add(double.parse(token));
      }
    }

    while (ops.isNotEmpty) {
      _applyOp(values, ops.removeLast());
    }

    return values.isNotEmpty ? values.last : 0;
  }

  int _precedence(String op) {
    if (op == '+' || op == '-') return 1;
    if (op == '*' || op == '/') return 2;
    return 0;
  }

  void _applyOp(List<double> values, String op) {
    if (values.length < 2) return;
    final b = values.removeLast();
    final a = values.removeLast();
    switch (op) {
      case '+':
        values.add(a + b);
        break;
      case '-':
        values.add(a - b);
        break;
      case '*':
        values.add(a * b);
        break;
      case '/':
        values.add(b != 0 ? a / b : 0);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;

    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              alignment: Alignment.bottomRight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  if (_expression.isNotEmpty)
                    Text(
                      _expression,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: glass.textSecondary,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    _display,
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.w300,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _CalcButton(
                      label: 'C',
                      onTap: _onClear,
                      color: glass.danger,
                      expanded: true,
                    ),
                    const SizedBox(width: 12),
                    _CalcButton(
                      label: '⌫',
                      onTap: _onBackspace,
                      expanded: true,
                    ),
                    const SizedBox(width: 12),
                    _CalcButton(label: '%', onTap: _onPercent, expanded: true),
                    const SizedBox(width: 12),
                    _CalcButton(
                      label: '÷',
                      onTap: () => _onOperator('÷'),
                      color: theme.colorScheme.primary,
                      expanded: true,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    _CalcButton(
                      label: '7',
                      onTap: () => _onNumber('7'),
                      expanded: true,
                    ),
                    const SizedBox(width: 12),
                    _CalcButton(
                      label: '8',
                      onTap: () => _onNumber('8'),
                      expanded: true,
                    ),
                    const SizedBox(width: 12),
                    _CalcButton(
                      label: '9',
                      onTap: () => _onNumber('9'),
                      expanded: true,
                    ),
                    const SizedBox(width: 12),
                    _CalcButton(
                      label: '×',
                      onTap: () => _onOperator('×'),
                      color: theme.colorScheme.primary,
                      expanded: true,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    _CalcButton(
                      label: '4',
                      onTap: () => _onNumber('4'),
                      expanded: true,
                    ),
                    const SizedBox(width: 12),
                    _CalcButton(
                      label: '5',
                      onTap: () => _onNumber('5'),
                      expanded: true,
                    ),
                    const SizedBox(width: 12),
                    _CalcButton(
                      label: '6',
                      onTap: () => _onNumber('6'),
                      expanded: true,
                    ),
                    const SizedBox(width: 12),
                    _CalcButton(
                      label: '-',
                      onTap: () => _onOperator('-'),
                      color: theme.colorScheme.primary,
                      expanded: true,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    _CalcButton(
                      label: '1',
                      onTap: () => _onNumber('1'),
                      expanded: true,
                    ),
                    const SizedBox(width: 12),
                    _CalcButton(
                      label: '2',
                      onTap: () => _onNumber('2'),
                      expanded: true,
                    ),
                    const SizedBox(width: 12),
                    _CalcButton(
                      label: '3',
                      onTap: () => _onNumber('3'),
                      expanded: true,
                    ),
                    const SizedBox(width: 12),
                    _CalcButton(
                      label: '+',
                      onTap: () => _onOperator('+'),
                      color: theme.colorScheme.primary,
                      expanded: true,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    _CalcButton(
                      label: '+/-',
                      onTap: _onSignToggle,
                      expanded: true,
                    ),
                    const SizedBox(width: 12),
                    _CalcButton(
                      label: '0',
                      onTap: () => _onNumber('0'),
                      expanded: true,
                    ),
                    const SizedBox(width: 12),
                    _CalcButton(
                      label: '.',
                      onTap: () => _onNumber('.'),
                      expanded: true,
                    ),
                    const SizedBox(width: 12),
                    _CalcButton(
                      label: '=',
                      onTap: _onEquals,
                      color: theme.colorScheme.primary,
                      expanded: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CalcButton extends StatelessWidget {
  const _CalcButton({
    required this.label,
    required this.onTap,
    this.color,
    this.expanded = false,
  });

  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final bgColor = color ?? glass.surfaceStrong;

    Widget child = Text(
      label,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: color != null ? Colors.white : theme.colorScheme.onSurface,
      ),
    );

    if (expanded) {
      child = Expanded(
        child: Material(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 60,
              alignment: Alignment.center,
              child: child,
            ),
          ),
        ),
      );
    } else {
      child = Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            child: child,
          ),
        ),
      );
    }

    return child;
  }
}
