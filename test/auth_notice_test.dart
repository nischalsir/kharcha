import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/errors/app_failure.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:kharcha_app/widgets/common/auth_widgets.dart';
import 'package:provider/provider.dart';

Future<AuthProvider> _pump(WidgetTester tester) async {
  final auth = AuthProvider();
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Column(children: <Widget>[AuthFailureNotice(), Text('form')]),
        ),
      ),
    ),
  );
  return auth;
}

void main() {
  testWidgets('nothing is shown, and no space taken, without a failure', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byType(SnackBar), findsNothing);
    expect(tester.getSize(find.byType(AuthFailureNotice)), Size.zero);
    // The form sits at the very top: no card above it.
    expect(tester.getTopLeft(find.text('form')).dy, 0);
  });

  testWidgets('a failure arrives as a notice at the bottom, not a card', (
    tester,
  ) async {
    final auth = await _pump(tester);
    auth.setError(FailureKind.syncFailed, 'Wrong email or password.');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    final snack = find.byType(SnackBar);
    expect(snack, findsOneWidget);
    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(tester.widget<SnackBar>(snack).behavior, SnackBarBehavior.floating);
    // In the lower half of the screen, and the form has not moved.
    final screen = tester.getSize(find.byType(MaterialApp)).height;
    expect(tester.getCenter(snack).dy, greaterThan(screen / 2));
    expect(tester.getTopLeft(find.text('form')).dy, 0);
  });

  testWidgets('it dismisses itself', (tester) async {
    final auth = await _pump(tester);
    auth.setError(FailureKind.syncFailed, 'Wrong email or password.');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.byType(SnackBar), findsOneWidget);

    // Past its five seconds and through the exit animation, a frame at a
    // time: the dismiss timer only starts once the notice has finished
    // sliding in.
    for (var second = 0; second < 9; second++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('one failure is announced once, however often it notifies', (
    tester,
  ) async {
    final auth = await _pump(tester);
    auth.setError(FailureKind.syncFailed, 'Wrong email or password.');
    await tester.pump();
    // Unrelated notifications while the same failure is still set.
    auth.notifyListeners();
    auth.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('Wrong email or password.'), findsOneWidget);
  });

  testWidgets('a new failure replaces the old notice instead of stacking', (
    tester,
  ) async {
    final auth = await _pump(tester);
    auth.setError(FailureKind.syncFailed, 'First problem.');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    auth.setError(FailureKind.syncFailed, 'Second problem.');
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Second problem.'), findsOneWidget);
    expect(find.text('First problem.'), findsNothing);
  });

  testWidgets('being offline is a warning with its own icon', (tester) async {
    final auth = await _pump(tester);
    auth.setError(FailureKind.offline, 'No internet connection.');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
  });

  testWidgets('success and warning notices use the same popup', (tester) async {
    await _pump(tester);
    final context = tester.element(find.text('form'));

    showAuthNotice(context, 'Password updated.', kind: AuthNoticeKind.success);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);

    showAuthNotice(context, 'Careful.', kind: AuthNoticeKind.warning);
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.text('Password updated.'), findsNothing);
  });
}
