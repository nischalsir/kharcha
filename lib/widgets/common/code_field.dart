import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/email_code.dart';

/// Keeps a code field to digits and to the length of a code, whatever is
/// typed or pasted into it.
class _CodeFormatter extends TextInputFormatter {
  const _CodeFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final code = EmailCode.clean(newValue.text);
    return TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
  }
}

/// Where an emailed code is entered: one box for each digit.
///
/// It is a single text field underneath, so the keyboard, autofill from a
/// message and pasting all work as they do anywhere else, and a pasted code
/// lands in every box at once. The boxes shrink to fit a narrow phone
/// rather than run off its edge.
class CodeField extends StatefulWidget {
  const CodeField({
    super.key,
    required this.controller,
    this.fieldKey,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.hasError = false,
    this.onChanged,
    this.onCompleted,
    this.onSubmitted,
  });

  final TextEditingController controller;

  /// Key for the text field itself.
  final Key? fieldKey;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;

  /// Draws the boxes in the error colour.
  final bool hasError;
  final ValueChanged<String>? onChanged;

  /// Called once every digit is in.
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onSubmitted;

  static const double _boxWidth = 40;
  static const double _boxHeight = 52;
  static const double _gap = 6;

  /// A wider space after the middle box, so eight digits read as two fours.
  static const double _middleGap = 14;

  @override
  State<CodeField> createState() => _CodeFieldState();
}

class _CodeFieldState extends State<CodeField> {
  FocusNode? _ownFocus;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(CodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.removeListener(_changed);
    _ownFocus?.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _onText(String value) {
    widget.onChanged?.call(value);
    if (EmailCode.isComplete(value)) widget.onCompleted?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final code = widget.controller.text;
    const count = EmailCode.length;
    const half = count ~/ 2;

    // As wide as the boxes like to be. Where there is less room than that
    // (a narrow phone, a dialog), the whole row is scaled down to fit rather
    // than running off the edge. Not measured with a LayoutBuilder: a dialog
    // sizes itself to its content and cannot ask one how wide it is.
    const natural =
        CodeField._boxWidth * count +
        CodeField._gap * (count - 2) +
        CodeField._middleGap;

    Widget box(int index) {
      final filled = index < code.length;
      final active =
          _focus.hasFocus &&
          index == math.min(code.length, count - 1) &&
          widget.enabled;
      final Color border = widget.hasError
          ? glass.danger
          : active
          ? theme.colorScheme.primary
          : glass.border.withValues(alpha: filled ? 0.9 : 0.5);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: CodeField._boxWidth,
        height: CodeField._boxHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: glass.fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: active ? 1.8 : 1.2),
        ),
        child: Text(
          filled ? code[index] : '',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 22,
            height: 1,
          ),
        ),
      );
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: natural,
        height: CodeField._boxHeight,
        child: Stack(
          children: <Widget>[
            // Drawn only: the field over them is what takes the input.
            ExcludeSemantics(
              child: Row(
                children: <Widget>[
                  for (var i = 0; i < count; i++) ...<Widget>[
                    if (i == half)
                      const SizedBox(width: CodeField._middleGap)
                    else if (i > 0)
                      const SizedBox(width: CodeField._gap),
                    box(i),
                  ],
                ],
              ),
            ),
            Positioned.fill(
              child: TextField(
                key: widget.fieldKey,
                controller: widget.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                enabled: widget.enabled,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.oneTimeCode],
                inputFormatters: const <TextInputFormatter>[_CodeFormatter()],
                // The boxes show the digits; the field's own text, cursor
                // and frame stay out of sight. Long-press still offers
                // Paste.
                showCursor: false,
                enableInteractiveSelection: true,
                style: const TextStyle(
                  color: Colors.transparent,
                  fontSize: 1,
                  height: 1,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  counterText: '',
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
                expands: true,
                maxLines: null,
                onChanged: _onText,
                onSubmitted: widget.onSubmitted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
