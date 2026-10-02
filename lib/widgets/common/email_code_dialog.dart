import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_failure.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/email_code.dart';
import '../../providers/auth_provider.dart';
import 'auth_widgets.dart';
import 'code_field.dart';

/// "Check the spam folder too": shown wherever a code has been emailed, since
/// that is where a first email from a new sender most often lands.
class SpamHint extends StatelessWidget {
  const SpamHint({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = context.glass.textSecondary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.report_gmailerrorred_rounded,
            size: 16,
            color: color,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            context.t(
              'Not in your inbox? Check your spam or junk folder too.',
              'इनबक्समा छैन? स्प्याम वा जंक फोल्डर पनि हेर्नुहोस्।',
            ),
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// What to say when a code that is too short is sent.
String incompleteCodeMessage(BuildContext context) => context.t(
  'Enter all ${EmailCode.length} digits of the code from the email.',
  'इमेलमा आएको कोडका ${L10n.neNumber(EmailCode.length)} वटै अंक लेख्नुहोस्।',
);

/// Asks for the code emailed when an account is created, and confirms the
/// account with it. Confirming signs the account in.
///
/// Pops `true` once that has happened, `false` when it is closed without.
class EmailCodeDialog extends StatefulWidget {
  const EmailCodeDialog({super.key, required this.email, this.sendNow = false});

  final String email;

  /// Email a fresh code as the dialog opens. For someone signing in to an
  /// account they never confirmed: the code from sign-up is long gone.
  final bool sendNow;

  /// How long before another code can be asked for.
  static const int resendAfterSeconds = 60;

  static Future<bool> show(
    BuildContext context, {
    required String email,
    bool sendNow = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EmailCodeDialog(email: email, sendNow: sendNow),
    );
    return confirmed ?? false;
  }

  @override
  State<EmailCodeDialog> createState() => _EmailCodeDialogState();
}

class _EmailCodeDialogState extends State<EmailCodeDialog> {
  final TextEditingController _code = TextEditingController();

  bool _busy = false;

  /// The code as it was when the server refused it; the boxes are drawn in
  /// the error colour until it is changed.
  String? _refused;

  /// Seconds until another code may be sent.
  int _wait = EmailCodeDialog.resendAfterSeconds;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _startWait();
    if (widget.sendNow) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resend());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startWait() {
    _ticker?.cancel();
    _wait = EmailCodeDialog.resendAfterSeconds;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _wait--);
      if (_wait <= 0) timer.cancel();
    });
  }

  String _messageOf(Object error) =>
      context.read<AuthProvider>().error ?? AppFailure.from(error).message;

  /// Said in a notice from the bottom of the screen, above this dialog, the
  /// same way every other sign-in problem is.
  void _say(String message, {AuthNoticeKind kind = AuthNoticeKind.error}) =>
      showOverlayNotice(context, message, kind: kind);

  Future<void> _verify() async {
    if (_busy) return;
    final code = EmailCode.clean(_code.text);
    if (!EmailCode.canSubmit(code)) {
      setState(() => _refused = _code.text);
      _say(incompleteCodeMessage(context));
      return;
    }
    setState(() {
      _busy = true;
      _refused = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      await auth.confirmSignUp(email: widget.email, code: code);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final message = _messageOf(error);
      // Said here, not on the page behind the dialog.
      auth.clearError();
      setState(() => _refused = _code.text);
      _say(message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _refused = null;
    });
    final auth = context.read<AuthProvider>();
    final sent = context.t('A new code is on its way.', 'नयाँ कोड पठाइँदैछ।');
    try {
      await auth.resendSignUpCode(widget.email);
      if (!mounted) return;
      _code.clear();
      setState(_startWait);
      _say(sent, kind: AuthNoticeKind.success);
    } catch (error) {
      if (!mounted) return;
      final message = _messageOf(error);
      auth.clearError();
      _say(message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Room for a box per digit on a narrow phone.
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(context.t('Confirm your email', 'इमेल पुष्टि गर्नुहोस्')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              context.t(
                'Enter the ${EmailCode.length}-digit code we sent to '
                    '${widget.email}.',
                '${widget.email} मा पठाइएको '
                    '${L10n.neNumber(EmailCode.length)} अंकको कोड लेख्नुहोस्।',
              ),
            ),
            const SizedBox(height: 8),
            const SpamHint(),
            const SizedBox(height: 18),
            Center(
              child: CodeField(
                controller: _code,
                fieldKey: const ValueKey<String>('email-code-field'),
                autofocus: true,
                enabled: !_busy,
                hasError: _refused != null && _refused == _code.text,
                // Every digit in: no need to reach for the button.
                onCompleted: (_) => _verify(),
                onSubmitted: (_) => _verify(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const ValueKey<String>('email-code-resend'),
                onPressed: _busy || _wait > 0 ? null : _resend,
                child: Text(
                  _wait > 0
                      ? context.t(
                          'Send again in ${_wait}s',
                          '${L10n.neNumber(_wait)} सेकेन्डमा फेरि पठाउनुहोस्',
                        )
                      : context.t('Send the code again', 'कोड फेरि पठाउनुहोस्'),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(context.t('Cancel', 'रद्द गर्नुहोस्')),
        ),
        FilledButton(
          key: const ValueKey<String>('email-code-verify'),
          onPressed: _busy ? null : _verify,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.t('Confirm', 'पुष्टि गर्नुहोस्')),
        ),
      ],
    );
  }
}
