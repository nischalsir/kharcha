import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/calculator.dart';
import 'form_helpers.dart';
import 'glass_sheet.dart';
import 'primary_button.dart';

/// Opens a calculator and returns the result as it should be typed into an
/// amount field, or null when dismissed. [initial] seeds it with what the
/// field already holds, so the user can carry on from that number.
Future<String?> showCalculatorSheet(BuildContext context, {String? initial}) {
  return showGlassSheet<String>(
    context: context,
    title: context.t('Calculator', 'क्याल्कुलेटर'),
    builder: (_) => _CalculatorPad(initial: initial),
  );
}

/// The calculator button for an amount field. Tapping it opens the calculator
/// and writes the result into [controller], where it can still be edited.
class CalculatorButton extends StatelessWidget {
  const CalculatorButton({super.key, required this.controller, this.onResult});

  final TextEditingController controller;

  /// Called after the field has been filled, e.g. to refresh a running total.
  final VoidCallback? onResult;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.t('Calculator', 'क्याल्कुलेटर'),
      icon: const Icon(Icons.calculate_outlined),
      color: Theme.of(context).colorScheme.primary,
      onPressed: () async {
        FocusScope.of(context).unfocus();
        final result = await showCalculatorSheet(
          context,
          initial: controller.text,
        );
        if (result == null) return;
        controller.value = TextEditingValue(
          text: result,
          selection: TextSelection.collapsed(offset: result.length),
        );
        onResult?.call();
      },
    );
  }
}

class _CalculatorPad extends StatefulWidget {
  const _CalculatorPad({this.initial});

  final String? initial;

  @override
  State<_CalculatorPad> createState() => _CalculatorPadState();
}

class _CalculatorPadState extends State<_CalculatorPad> {
  static const String _operators = '+−×÷';

  late String _expr;

  @override
  void initState() {
    super.initState();
    final seed = parseAmount(widget.initial ?? '');
    _expr = seed == null || seed == 0 ? '' : formatCalculatorResult(seed);
  }

  double? get _result => evaluateExpression(_expr);

  /// The amount "Use" would return: a finished, storable, non-negative sum.
  String? get _usable {
    final value = _result;
    if (value == null || value < 0 || value > kMaxAmount) return null;
    return formatCalculatorResult(value);
  }

  bool get _endsWithOperator =>
      _expr.isNotEmpty && _operators.contains(_expr[_expr.length - 1]);

  /// The number currently being typed (after the last operator).
  String get _currentNumber {
    var i = _expr.length;
    while (i > 0 && !_operators.contains(_expr[i - 1])) {
      i--;
    }
    return _expr.substring(i);
  }

  void _tap(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      switch (key) {
        case 'C':
          _expr = '';
        case '⌫':
          if (_expr.isNotEmpty) _expr = _expr.substring(0, _expr.length - 1);
        case '=':
          final value = _result;
          if (value != null) _expr = formatCalculatorResult(value);
        case '.':
          final number = _currentNumber;
          if (number.contains('.')) return;
          _expr += number.isEmpty ? '0.' : '.';
        case '+' || '−' || '×' || '÷':
          if (_expr.isEmpty) {
            // Only a minus may start an expression.
            if (key == '−') _expr = '−';
            return;
          }
          if (_expr == '−') return;
          // A second operator replaces the first instead of stacking up.
          if (_endsWithOperator) {
            _expr = _expr.substring(0, _expr.length - 1);
          }
          _expr += key;
        default:
          // Paisa only: stop a third decimal digit being typed.
          final number = _currentNumber;
          final dot = number.indexOf('.');
          if (dot >= 0 && number.length - dot > 2) return;
          if (_expr.length >= 40) return;
          _expr += key;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final result = _result;
    final usable = _usable;
    final showsPreview =
        result != null && _expr != formatCalculatorResult(result);

    Widget key(String label, {bool accent = false, int flex = 1}) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Material(
            color: accent
                ? theme.colorScheme.primary.withValues(alpha: 0.14)
                : glass.fill,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _tap(label),
              child: SizedBox(
                height: 54,
                child: Center(
                  child: Text(
                    label,
                    semanticsLabel: switch (label) {
                      '⌫' => 'Delete',
                      'C' => 'Clear',
                      '÷' => 'Divide',
                      '×' => 'Multiply',
                      '−' => 'Minus',
                      '+' => 'Plus',
                      '=' => 'Equals',
                      _ => label,
                    },
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: accent
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: glass.fill,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  _expr.isEmpty ? '0' : _expr,
                  maxLines: 1,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                showsPreview ? '= ${formatCalculatorResult(result)}' : ' ',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: glass.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            key('C', accent: true),
            key('⌫', accent: true),
            key('÷', accent: true, flex: 2),
          ],
        ),
        Row(
          children: <Widget>[
            key('7'),
            key('8'),
            key('9'),
            key('×', accent: true),
          ],
        ),
        Row(
          children: <Widget>[
            key('4'),
            key('5'),
            key('6'),
            key('−', accent: true),
          ],
        ),
        Row(
          children: <Widget>[
            key('1'),
            key('2'),
            key('3'),
            key('+', accent: true),
          ],
        ),
        Row(
          children: <Widget>[
            key('0', flex: 2),
            key('.'),
            key('=', accent: true),
          ],
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: PrimaryButton(
            label: usable == null
                ? context.t('Use amount', 'रकम प्रयोग गर्नुहोस्')
                : context.t('Use $usable', '$usable प्रयोग गर्नुहोस्'),
            icon: Icons.check_rounded,
            onPressed: usable == null
                ? null
                : () => Navigator.of(context).pop(usable),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
