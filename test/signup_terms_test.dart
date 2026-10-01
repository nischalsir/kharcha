import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:kharcha_app/screens/auth/signup_screen.dart';
import 'package:kharcha_app/services/biometric_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:provider/provider.dart';

const Color _red = Color(0xffff453a);
const Color _green = Color(0xff30d158);

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(480, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        Provider<BiometricService>(create: (_) => BiometricService()),
        Provider<NepaliDateService>(create: (_) => NepaliDateService()),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const SignupScreen()),
    ),
  );
  await tester.pump();
}

/// The colour of the glow around the terms tick box, or null when it has none.
Color? _glow(WidgetTester tester) {
  final box = tester.widget<AnimatedContainer>(
    find
        .ancestor(
          of: find.byType(Checkbox),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  final shadows = (box.decoration! as BoxDecoration).boxShadow ?? const [];
  return shadows.isEmpty ? null : shadows.first.color.withValues(alpha: 1);
}

Future<void> _fillForm(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'Test User');
  await tester.enterText(fields.at(1), 'test@example.com');
  await tester.enterText(fields.at(2), 'secret1');
  await tester.enterText(fields.at(3), 'secret1');
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Create account').last);
  await tester.tap(find.text('Create account').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the tick box has no glow before anything is tried', (
    tester,
  ) async {
    await _pump(tester);
    expect(_glow(tester), isNull);

    // Ticking it on its own does not light it up either.
    await tester.tap(find.byType(Checkbox));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_glow(tester), isNull);
  });

  testWidgets('signing up without agreeing glows red, with no error card', (
    tester,
  ) async {
    await _pump(tester);
    await _fillForm(tester);
    await _submit(tester);

    expect(_glow(tester), _red);
    // The old behaviour put a banner at the top of the form.
    expect(find.textContaining('agree to the Terms of Service'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('it is flagged even while other fields still have errors', (
    tester,
  ) async {
    await _pump(tester);
    // Nothing filled in at all: every field is invalid as well.
    await _submit(tester);

    expect(_glow(tester), _red);
    expect(find.text('Email is required'), findsOneWidget);
  });

  testWidgets('the terms link still opens the terms', (tester) async {
    await _pump(tester);
    await tester.ensureVisible(find.text('Terms'));
    await tester.tap(find.text('Terms'));
    await tester.pumpAndSettle();

    expect(find.text('Terms of Service'), findsOneWidget);
  });

  testWidgets('ticking it afterwards turns the glow green', (tester) async {
    await _pump(tester);
    await _fillForm(tester);
    await _submit(tester);
    expect(_glow(tester), _red);

    await tester.tap(find.byType(Checkbox));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_glow(tester), _green);

    // And back to red if it is unticked again.
    await tester.tap(find.byType(Checkbox));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_glow(tester), _red);
  });
}
