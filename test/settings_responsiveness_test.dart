import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/l10n/app_l10n.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:provider/provider.dart';

void main() {
  test('theme is built once, so a settings rebuild does not restart the '
      'theme animation', () {
    // The app rebuilds MaterialApp whenever settings (or sync status) notify.
    // A fresh ThemeData each time never compares equal - the extensions have
    // identity equality - so AnimatedTheme re-lerps the whole app for 200ms.
    expect(identical(AppTheme.light(), AppTheme.light()), isTrue);
    expect(identical(AppTheme.dark(), AppTheme.dark()), isTrue);
  });

  testWidgets('language switch rebuilds text that is not watching settings', (
    tester,
  ) async {
    final dates = NepaliDateService();
    final language = ValueNotifier<bool>(false);

    await tester.pumpWidget(
      Provider<NepaliDateService>.value(
        value: dates,
        child: ValueListenableBuilder<bool>(
          valueListenable: language,
          builder: (_, nepali, _) => LanguageScope(
            nepali: nepali,
            // const: exactly like RootShell under the auth wrapper, this child
            // is never rebuilt by its parent.
            child: const MaterialApp(home: _Label()),
          ),
        ),
      ),
    );
    expect(find.text('Hello'), findsOneWidget);

    dates.devanagari = true;
    language.value = true;
    await tester.pump();

    expect(find.text('नमस्ते'), findsOneWidget);
  });
}

class _Label extends StatelessWidget {
  const _Label();

  @override
  Widget build(BuildContext context) => Text(context.t('Hello', 'नमस्ते'));
}
