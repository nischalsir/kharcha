import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';

void main() {
  test('theme is built once, so a settings rebuild does not restart the '
      'theme animation', () {
    // The app rebuilds MaterialApp whenever settings (or sync status) notify.
    // A fresh ThemeData each time would never compare equal - the extensions
    // have identity equality - and AnimatedTheme would re-lerp the whole app.
    expect(identical(AppTheme.light(), AppTheme.light()), isTrue);
    expect(identical(AppTheme.dark(), AppTheme.dark()), isTrue);
  });
}
