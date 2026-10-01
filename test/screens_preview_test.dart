import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/models/financial_summary.dart';
import 'package:kharcha_app/models/payment_method.dart';
import 'package:kharcha_app/models/statement_entry.dart';
import 'package:kharcha_app/models/transaction_model.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:kharcha_app/providers/transaction_provider.dart';
import 'package:kharcha_app/providers/update_provider.dart';
import 'package:kharcha_app/repositories/transaction_repository.dart';
import 'package:kharcha_app/screens/auth/signup_screen.dart';
import 'package:kharcha_app/screens/more/more_screen.dart';
import 'package:kharcha_app/screens/payments/statement_import_screen.dart';
import 'package:kharcha_app/services/biometric_service.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/flamey_controller.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:kharcha_app/widgets/common/ai_mood_badge.dart';
import 'package:kharcha_app/widgets/common/glass_background.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Draws the screens changed in this release into `build/previews/*.png`, so
/// they can be looked at without a phone. Skipped unless asked for:
///
///   flutter test test/screens_preview_test.dart --dart-define=PREVIEWS=true
///
/// (with FLUTTER_ROOT set, for the fonts).
void main() {
  const enabled = bool.fromEnvironment('PREVIEWS');

  Future<void> loadFonts() async {
    final root =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    Future<ByteData> read(String name) async =>
        ByteData.sublistView(await File('$root/$name').readAsBytes());
    await (FontLoader(
      'MaterialIcons',
    )..addFont(read('materialicons-regular.otf'))).load();
    final roboto = FontLoader('Roboto');
    for (final file in <String>[
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
      'roboto-black.ttf',
    ]) {
      roboto.addFont(read(file));
    }
    await roboto.load();
  }

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget child, {
    Size size = const Size(390, 844),
    bool dark = false,
    List<InheritedProvider<dynamic>> providers =
        const <InheritedProvider<dynamic>>[],
    Future<void> Function()? act,
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final theme = (dark ? AppTheme.dark() : AppTheme.light()).copyWith(
      textTheme: (dark ? AppTheme.dark() : AppTheme.light()).textTheme.apply(
        fontFamily: 'Roboto',
      ),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: <InheritedProvider<dynamic>>[
          Provider<NepaliDateService>(create: (_) => NepaliDateService()),
          ...providers,
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: RepaintBoundary(
            key: key,
            child: GlassBackground(
              child: Scaffold(backgroundColor: Colors.transparent, body: child),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    if (act != null) await act();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('build/previews/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('draws the changed screens', (tester) async {
    await tester.runAsync(loadFonts);
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});

    List<InheritedProvider<dynamic>> account() => <InheritedProvider<dynamic>>[
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ChangeNotifierProvider<UpdateProvider>(create: (_) => UpdateProvider()),
      Provider<BiometricService>(create: (_) => BiometricService()),
    ];

    await shoot(tester, 'more-light', const MoreScreen(), providers: account());
    await shoot(
      tester,
      'more-dark',
      const MoreScreen(),
      dark: true,
      providers: account(),
    );
    await shoot(
      tester,
      'more-small',
      const MoreScreen(),
      size: const Size(320, 640),
      providers: account(),
    );

    await shoot(
      tester,
      'signup-terms',
      const SignupScreen(),
      size: const Size(390, 1200),
      providers: account(),
      act: () async {
        await tester.ensureVisible(find.text('Create account').last);
        await tester.tap(find.text('Create account').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      },
    );

    // The import screen: the start, and a review with a flagged row.
    final cache = await CacheService.create();
    final sync = SyncService(cache: cache, remote: SupabaseService());
    List<InheritedProvider<dynamic>> importing() =>
        <InheritedProvider<dynamic>>[
          ChangeNotifierProvider<TransactionProvider>(
            create: (_) => TransactionProvider(
              cache: cache,
              repository: TransactionRepository(cache, sync),
            ),
          ),
        ];
    await shoot(
      tester,
      'import-start',
      const StatementImportScreen(),
      providers: importing(),
    );
    final entries = <StatementEntry>[
      StatementEntry(
        occurredAt: DateTime(2025, 1, 20),
        title: 'eSewa Wallet Load',
        amount: 1500,
        type: TransactionType.expense,
        paymentMethod: PaymentMethod.esewa,
        reference: 'FT25020881',
      ),
      StatementEntry(
        occurredAt: DateTime(2025, 1, 18),
        title: 'IPS/Remit Received',
        amount: 12000,
        type: TransactionType.income,
        paymentMethod: PaymentMethod.bank,
      ),
      StatementEntry(
        occurredAt: DateTime(2025, 1, 15),
        title: 'POS Bhatbhateni Supermarket',
        amount: 4200,
        type: TransactionType.expense,
        paymentMethod: PaymentMethod.card,
        warning: 'Does not match the running balance on the statement',
      ),
    ];
    StatementEntry.assignFingerprints(entries);
    await shoot(
      tester,
      'import-review',
      StatementImportScreen(
        initialResult: StatementParseResult(
          entries: entries,
          skipped: const <SkippedStatementRow>[
            SkippedStatementRow(
              row: 0,
              page: 2,
              reason: 'Date not recognised',
              text: '31/02/2025 No such day 50.00',
            ),
          ],
          source: StatementSource.bank,
          provider: 'Nabil Bank',
          unreadPages: const <int>[3],
          pageCount: 3,
          balanceChecked: true,
        ),
      ),
      providers: importing(),
    );

    // Flamey on the balance card, mid-reaction.
    final flamey = FlameyController();
    await shoot(
      tester,
      'flamey-badge',
      const Center(
        child: SizedBox(
          width: 320,
          child: Align(
            alignment: Alignment.centerRight,
            child: AiMoodBadge(
              mood: AiMood(
                emoji: '🙂',
                label: 'On track',
                message: 'Steady month so far.',
                tone: MoodTone.good,
                face: MoodFace.happy,
                energy: 0.8,
              ),
            ),
          ),
        ),
      ),
      size: const Size(360, 160),
      providers: <InheritedProvider<dynamic>>[
        ChangeNotifierProvider<FlameyController>.value(value: flamey),
      ],
      act: () async {
        flamey.tap();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
    flamey.dispose();
  }, skip: !enabled);
}
