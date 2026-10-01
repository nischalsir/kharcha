import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:kharcha_app/screens/settings/change_password_screen.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';

const String _sameWarning = 'New password must be different from old password';

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        Provider<NepaliDateService>(create: (_) => NepaliDateService()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const ChangePasswordScreen(),
      ),
    ),
  );
}

void main() {
  testWidgets('reusing the old password is flagged on the new fields', (
    tester,
  ) async {
    await _pump(tester);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'secret1');
    await tester.enterText(fields.at(1), 'secret1');
    await tester.enterText(fields.at(2), 'secret1');
    await tester.tap(find.text('Update password'));
    await tester.pump();

    // New password and its confirmation both carry the warning; the old
    // password field, which is not the one at fault, carries none.
    expect(find.text(_sameWarning), findsNWidgets(2));
    expect(
      find.descendant(of: fields.at(0), matching: find.text(_sameWarning)),
      findsNothing,
    );
  });

  testWidgets('a different new password raises no warning', (tester) async {
    await _pump(tester);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'secret1');
    await tester.enterText(fields.at(1), 'secret2');
    await tester.enterText(fields.at(2), 'secret3');
    await tester.tap(find.text('Update password'));
    await tester.pump();

    expect(find.text(_sameWarning), findsNothing);
    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  test('recognises the server refusing a reused password', () {
    expect(
      AuthProvider.isSamePasswordError(
        const AuthException('x', code: 'same_password'),
      ),
      isTrue,
    );
    expect(
      AuthProvider.isSamePasswordError(
        const AuthException(
          'New password should be different from the old password.',
        ),
      ),
      isTrue,
    );
    expect(
      AuthProvider.isSamePasswordError(const AuthException('Token expired')),
      isFalse,
    );
  });
}
