import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/main.dart';
import 'package:kharcha_app/providers/app_providers.dart';
import 'package:kharcha_app/screens/auth/introduction_screen.dart';
import 'package:kharcha_app/services/flamey_controller.dart';
import 'package:kharcha_app/services/incoming_file_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Starts the whole app the way `main` does, with the platform plugins
/// answered by the test, and checks it comes up: every provider the screens
/// read is in place, and the first screen is the one a new user should see.
///
/// This is the closest to "the app starts" that can be checked without a
/// phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app starts on the introduction for a new user', (
    tester,
  ) async {
    // A small phone in portrait, the only orientation the app allows.
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // Plugins the app talks to at start-up, answered quietly.
    for (final name in <String>[
      'dev.fluttercommunity.plus/connectivity',
      'dev.fluttercommunity.plus/connectivity_status',
      'plugins.flutter.io/firebase_messaging',
      'plugins.flutter.io/firebase_core',
      'dexterous.com/flutter/local_notifications',
      IncomingFileService.channelName,
      'com.nischalpandey.kharcha/app_config',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        if (call.method == 'check') return <String>['wifi'];
        return null;
      });
    }

    late AppEnvironment env;
    await tester.runAsync(() async {
      env = await AppEnvironment.bootstrap();
    });
    await tester.pumpWidget(KharchaApp(env: env));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(find.byType(IntroductionScreen), findsOneWidget);

    // The things the screens reach for are all there.
    final context = tester.element(find.byType(IntroductionScreen));
    expect(context.read<FlameyController>(), isNotNull);
    expect(context.read<IncomingFileService>(), isNotNull);

    // Leave cleanly: no timer left running behind the app.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    env.sync.dispose();
  });
}
