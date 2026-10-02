import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/widgets/common/email_code_dialog.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<bool>> open(WidgetTester tester, AuthProvider auth) async {
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

  testWidgets('says where the code went and to look in spam too', (
    tester,
  ) async {
    await open(tester, AuthProvider());
    expect(find.textContaining('me@example.com'), findsOneWidget);
    expect(find.textContaining('spam or junk folder'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only six digits are a code', (tester) async {
    final auth = AuthProvider();
    await open(tester, auth);

    await tester.tap(verify);
    await tester.pump();
    expect(find.text('Enter the 6-digit code'), findsOneWidget);

    // Letters are not typed at all, and five digits are not enough.
    await tester.enterText(field, '12a45');
    await tester.tap(verify);
    await tester.pump();
    expect(find.text('1245'), findsOneWidget);
    expect(find.text('Enter the 6-digit code'), findsOneWidget);
  });

  testWidgets('a code that does not work is said by the field', (tester) async {
    // No backend in a test: confirming fails, the way a wrong code does.
    final auth = AuthProvider();
    final results = await open(tester, auth);

    await tester.enterText(field, '123456');
    await tester.tap(verify);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey<String>('email-code-error')),
      findsOneWidget,
    );
    // Still open, and nothing left on the page behind it.
    expect(verify, findsOneWidget);
    expect(auth.failure, isNull);
    expect(results, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(results, <bool>[false]);
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
