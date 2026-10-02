import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/core/utils/email_code.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/widgets/common/auth_widgets.dart';
import 'package:kharcha_app/widgets/common/code_field.dart';
import 'package:kharcha_app/widgets/common/email_code_dialog.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A notice takes itself down after a few seconds; no test waits for it.
  tearDown(dismissOverlayNotice);

  Future<List<bool>> open(
    WidgetTester tester,
    AuthProvider auth, {
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final results = <bool>[];
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          Provider<NepaliDateService>(create: (_) => NepaliDateService()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => results.add(
                  await EmailCodeDialog.show(context, email: 'me@example.com'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return results;
  }

  final verify = find.byKey(const ValueKey<String>('email-code-verify'));
  final field = find.byKey(const ValueKey<String>('email-code-field'));
  final resend = find.byKey(const ValueKey<String>('email-code-resend'));
  final notice = find.byKey(const ValueKey<String>('overlay-notice'));

  String typed(WidgetTester tester) =>
      tester.widget<TextField>(field).controller!.text;

  group('what counts as a code', () {
    test('the app expects the eight digits the server sends', () {
      expect(EmailCode.length, 8);
      expect(EmailCode.isComplete('12345678'), isTrue);
      expect(EmailCode.isComplete('1234567'), isFalse);
      expect(EmailCode.canSubmit('12345678'), isTrue);
    });

    test('a paste is read for its digits, however it is written', () {
      expect(EmailCode.clean('12345678'), '12345678');
      expect(EmailCode.clean('1234 5678'), '12345678');
      expect(EmailCode.clean('1234-5678'), '12345678');
      expect(EmailCode.clean(' Your Kharcha code: 12345678. '), '12345678');
      // Never longer than a code.
      expect(EmailCode.clean('123456789012'), '12345678');
      expect(EmailCode.clean('no digits'), '');
    });

    test('too short to send, and the shortest the server could send', () {
      expect(EmailCode.canSubmit(''), isFalse);
      expect(EmailCode.canSubmit('12345'), isFalse);
      // The server can be set to six: such a code is not refused here.
      expect(EmailCode.canSubmit('123456'), isTrue);
    });
  });

  testWidgets('says where the code went and to look in spam too', (
    tester,
  ) async {
    await open(tester, AuthProvider());
    expect(find.textContaining('me@example.com'), findsOneWidget);
    expect(find.textContaining('8-digit code'), findsOneWidget);
    expect(find.textContaining('6-digit'), findsNothing);
    expect(find.textContaining('spam or junk folder'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all eight digits can be typed, one box each', (tester) async {
    await open(tester, AuthProvider());
    await tester.enterText(field, '12345678');
    await tester.pump();

    expect(typed(tester), '12345678');
    // Each digit is drawn in a box of its own.
    for (final digit in '12345678'.split('')) {
      expect(
        find.descendant(of: find.byType(CodeField), matching: find.text(digit)),
        findsOneWidget,
      );
    }
    // A number keyboard, and the phone may offer the code from the message.
    final input = tester.widget<TextField>(field);
    expect(input.keyboardType, TextInputType.number);
    expect(input.autofillHints, contains(AutofillHints.oneTimeCode));
    expect(input.autofocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pasted code fills every box, spaces and words left out', (
    tester,
  ) async {
    await open(tester, AuthProvider());
    // What a paste delivers: the whole text at once.
    await tester.enterText(field, 'Your code is 1234 5678');
    await tester.pump();
    expect(typed(tester), '12345678');

    // More than a code is cut to a code.
    await tester.enterText(field, '9876543210');
    await tester.pump();
    expect(typed(tester), '98765432');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an incomplete code is said in a notice from the bottom', (
    tester,
  ) async {
    final auth = AuthProvider();
    final results = await open(tester, auth);

    // Nothing typed.
    await tester.tap(verify);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(notice, findsOneWidget);
    expect(
      find.descendant(
        of: notice,
        matching: find.textContaining('all 8 digits'),
      ),
      findsOneWidget,
    );

    // Drawn over the dialog, at the bottom of the screen.
    final dialog = tester.getRect(find.byType(AlertDialog));
    final rect = tester.getRect(notice);
    expect(rect.bottom, greaterThan(dialog.center.dy));
    expect(rect.bottom, lessThanOrEqualTo(800));

    // A few digits are still not a code.
    await tester.enterText(field, '1234');
    await tester.tap(verify);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(
        of: notice,
        matching: find.textContaining('all 8 digits'),
      ),
      findsOneWidget,
    );
    // Still open; nothing was sent, and nothing is said behind the dialog.
    expect(verify, findsOneWidget);
    expect(auth.failure, isNull);
    expect(results, isEmpty);
  });

  testWidgets('a code the server refuses is said in a notice too', (
    tester,
  ) async {
    // No backend in a test: confirming fails, the way a wrong code does.
    final auth = AuthProvider();
    final results = await open(tester, auth);

    await tester.enterText(field, '1234567');
    await tester.tap(verify);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(notice, findsOneWidget);
    expect(verify, findsOneWidget);
    expect(auth.failure, isNull);
    expect(results, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(results, <bool>[false]);
  });

  testWidgets('the eighth digit sends the code without reaching for a button', (
    tester,
  ) async {
    final auth = AuthProvider();
    await open(tester, auth);
    await tester.enterText(field, '12345678');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // It was sent (and, with no backend here, refused): the notice is up.
    expect(notice, findsOneWidget);
  });

  testWidgets('the boxes fit a narrow phone', (tester) async {
    await open(tester, AuthProvider(), size: const Size(320, 640));
    await tester.enterText(field, '12345678');
    await tester.pump();
    expect(tester.takeException(), isNull);

    final boxes = tester.getRect(find.byType(CodeField));
    final dialog = tester.getRect(find.byType(AlertDialog));
    expect(boxes.left, greaterThanOrEqualTo(dialog.left));
    expect(boxes.right, lessThanOrEqualTo(dialog.right));
    expect(boxes.width, lessThanOrEqualTo(320));
  });

  testWidgets('another code can only be asked for after a wait', (
    tester,
  ) async {
    await open(tester, AuthProvider());
    TextButton button() => tester.widget<TextButton>(resend);

    expect(button().onPressed, isNull);
    expect(find.text('Send again in 60s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Send again in 50s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 50));
    expect(find.text('Send the code again'), findsOneWidget);
    expect(button().onPressed, isNotNull);
  });

  group('what the server says about codes', () {
    String said(String message, {String? code}) =>
        AuthProvider.describeAuthError(
          AuthException(message, statusCode: '400', code: code),
        ).message;

    test('an unconfirmed email is not called a wrong password', () {
      const error = AuthException(
        'Email not confirmed',
        statusCode: '400',
        code: 'email_not_confirmed',
      );
      expect(AuthProvider.isEmailNotConfirmed(error), isTrue);
      expect(AuthProvider.isWrongCredentials(error), isFalse);
      expect(said('Email not confirmed'), contains('not been confirmed'));
      expect(
        AuthProvider.isEmailNotConfirmed(
          const AuthException('Invalid login credentials'),
        ),
        isFalse,
      );
    });

    test('a wrong or old code, and asking too often', () {
      expect(
        said('Token has expired or is invalid', code: 'otp_expired'),
        contains('wrong or has expired'),
      );
      expect(
        said(
          'For security purposes, you can only request this after 42 seconds.',
        ),
        contains('Wait a minute'),
      );
      expect(
        said('Email rate limit exceeded', code: 'over_email_send_rate_limit'),
        contains('Wait a minute'),
      );
    });
  });
}
