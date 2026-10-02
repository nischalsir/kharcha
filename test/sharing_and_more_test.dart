import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage;
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/router/route_paths.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/main.dart';
import 'package:kharcha_app/models/statement_entry.dart';
import 'package:kharcha_app/providers/auth_provider.dart';
import 'package:kharcha_app/providers/transaction_provider.dart';
import 'package:kharcha_app/providers/update_provider.dart';
import 'package:kharcha_app/repositories/transaction_repository.dart';
import 'package:kharcha_app/screens/more/more_screen.dart';
import 'package:kharcha_app/screens/payments/statement_import_screen.dart';
import 'package:kharcha_app/services/biometric_service.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/incoming_file_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/statement_import_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:kharcha_app/services/update_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for Android's file picker: records what the app asked for and
/// hands back one file.
class _FakePicker extends FilePickerPlatform {
  _FakePicker(this.file);

  final PlatformFile file;
  FileType? type;
  List<String>? allowedExtensions;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    this.type = type;
    this.allowedExtensions = allowedExtensions;
    return file;
  }
}

/// A picked file held in memory.
final class _PickedFile extends PlatformFile {
  _PickedFile(this.name, this._bytes);

  @override
  final String name;
  final Uint8List _bytes;

  @override
  Uri get uri => Uri.parse('content://picked/$name');

  @override
  get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => _bytes.length;

  @override
  Future<int?> length() async => _bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream<Uint8List>.value(_bytes);
}

/// Reads nothing over the network: hands back a canned result and records
/// what it was given.
class _FakeReader extends StatementImportService {
  Uint8List? bytes;
  StatementSource? hint;

  @override
  Future<StatementParseResult> parseStatement(
    Uint8List bytes, {
    StatementSource? hint,
  }) async {
    this.bytes = bytes;
    this.hint = hint;
    return StatementParseResult.fromJson(<String, dynamic>{
      'source': 'bank',
      'provider': 'Nabil Bank',
      'kind': 'pdf',
      'pageCount': 2,
      'unreadPages': <int>[2],
      'balanceChecked': true,
      'entries': <Map<String, dynamic>>[
        <String, dynamic>{
          'occurred_at': '2025-01-20 00:00:00',
          'description': 'eSewa Wallet Load',
          'amount': 1500,
          'type': 'expense',
          'ref': 'FT25020881',
          'balance': 20300,
        },
      ],
      'skipped': <dynamic>[],
    });
  }
}

class _Updates extends UpdateService {
  @override
  Future<UpdateInfo?> fetchLatest() async => const UpdateInfo(
    version: '9.9.9',
    downloadUrl: 'https://example.com/kharcha.apk',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('files shared into the app', () {
    const channel = MethodChannel(IncomingFileService.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('the file the app was opened with is handed over once', () async {
      final dir = await Directory.systemTemp.createTemp('incoming');
      final copy = File('${dir.path}/statement.pdf')
        ..writeAsBytesSync(<int>[0x25, 0x50, 0x44, 0x46, 1, 2, 3, 4]);
      var asked = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'takeInitial');
        asked++;
        return asked == 1
            ? <String, Object>{
                'path': copy.path,
                'name': 'Statement_Jan.pdf',
                'mimeType': 'application/pdf',
                'size': 8,
              }
            : null;
      });
      final service = IncomingFileService(channel: channel);
      final file = await service.takeInitial();
      expect(file!.name, 'Statement_Jan.pdf');
      expect(file.looksSupported, isTrue);
      expect(await service.takeInitial(), isNull);

      // Reading it removes the private copy: a statement is not left behind.
      expect((await service.read(file)).length, 8);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(copy.existsSync(), isFalse);
      service.dispose();
      await dir.delete(recursive: true);
    });

    test('a share while the app is open arrives on the stream', () async {
      final service = IncomingFileService(channel: channel);
      final next = service.files.first;
      await messenger.handlePlatformMessage(
        IncomingFileService.channelName,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('incomingFile', <String, Object>{
            'error': 'too_large',
            'name': 'huge.pdf',
          }),
        ),
        (_) {},
      );
      final file = await next;
      expect(file.error, 'too_large');
      expect(file.path, isNull);
      service.dispose();
    });

    test('what counts as a statement file', () {
      IncomingFile named(String name, [String? mime]) =>
          IncomingFile(name: name, path: '/x', mimeType: mime);
      expect(named('a.PDF').looksSupported, isTrue);
      expect(named('a.xlsx').looksSupported, isTrue);
      expect(named('a.csv').looksSupported, isTrue);
      expect(named('download', 'application/pdf').looksSupported, isTrue);
      expect(named('photo.jpg', 'image/jpeg').looksSupported, isFalse);
      expect(IncomingFile.fromMap(<String, Object>{'name': 'x'}), isNull);
    });

    test('content is checked before anything is uploaded', () {
      Uint8List bytes(List<int> b) => Uint8List.fromList(b);
      expect(
        StatementImportService.looksLikeStatementFile(
          bytes(<int>[0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x37]),
        ),
        isTrue,
      );
      expect(
        StatementImportService.looksLikeStatementFile(
          bytes('Date,Description,Amount\n2025-01-01,Tea,50\n'.codeUnits),
        ),
        isTrue,
      );
      // A JPEG renamed to .pdf is still a JPEG.
      expect(
        StatementImportService.looksLikeStatementFile(
          bytes(<int>[0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46]),
        ),
        isFalse,
      );
    });

    Future<TransactionProvider> transactions(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => <String>['wifi'],
      );
      late CacheService cache;
      late SyncService sync;
      await tester.runAsync(() async {
        cache = await CacheService.create();
        sync = SyncService(cache: cache, remote: SupabaseService());
      });
      addTearDown(sync.dispose);
      return TransactionProvider(
        cache: cache,
        repository: TransactionRepository(cache, sync),
      );
    }

    Future<void> openWith(
      WidgetTester tester,
      TransactionProvider provider,
      IncomingFile file,
      IncomingFileService files,
      StatementImportService reader,
    ) async {
      tester.view.physicalSize = const Size(440, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: <InheritedProvider<dynamic>>[
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
            ChangeNotifierProvider<TransactionProvider>.value(value: provider),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: StatementImportScreen(
              incoming: file,
              incomingFiles: files,
              service: reader,
            ),
          ),
        ),
      );
      // The file is read for real; let that and the reply finish.
      for (var i = 0; i < 6; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }
      await tester.pump();
    }

    testWidgets('Choose file takes any file; its contents say what it is', (
      tester,
    ) async {
      // A statement saved under a name Android does not recognise as a PDF.
      final pdf = Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46, 9, 9, 9, 9]);
      final picker = _FakePicker(_PickedFile('1790697163863', pdf));
      final before = FilePickerPlatform.instance;
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = before);

      final reader = _FakeReader();
      final provider = await transactions(tester);
      tester.view.physicalSize = const Size(440, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: <InheritedProvider<dynamic>>[
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
            ChangeNotifierProvider<TransactionProvider>.value(value: provider),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: StatementImportScreen(service: reader),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Choose file'));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }
      await tester.pump();

      // Nothing is filtered by type: a filter is what made real statements
      // impossible to tap in Android's picker.
      expect(picker.type, FileType.any);
      expect(picker.allowedExtensions, isNull);
      expect(reader.bytes, pdf);
      expect(find.text('Import 1'), findsOneWidget);
    });

    testWidgets('a shared PDF goes straight to the review', (tester) async {
      final dir = Directory.systemTemp.createTempSync('shared');
      final copy = File('${dir.path}/s.pdf')
        ..writeAsBytesSync(<int>[0x25, 0x50, 0x44, 0x46, 9, 9, 9, 9]);
      final reader = _FakeReader();
      final provider = await transactions(tester);
      await openWith(
        tester,
        provider,
        IncomingFile(name: 'Statement.pdf', path: copy.path),
        IncomingFileService(channel: const MethodChannel('unused')),
        reader,
      );

      expect(reader.bytes, isNotNull);
      // No source is guessed for it: the file says what it is.
      expect(reader.hint, isNull);
      expect(find.text('Statement.pdf'), findsOneWidget);
      expect(find.textContaining('Nabil Bank statement'), findsOneWidget);
      expect(find.textContaining('page 2 of 2'), findsOneWidget);
      expect(find.text('Import 1'), findsOneWidget);
      // Nothing is saved before the user confirms.
      expect(provider.statementMatchKeys(), isEmpty);
      dir.deleteSync(recursive: true);
    });

    testWidgets('a shared file that is too big is explained, with a way on', (
      tester,
    ) async {
      final reader = _FakeReader();
      await openWith(
        tester,
        await transactions(tester),
        const IncomingFile(name: 'huge.pdf', error: 'too_large'),
        IncomingFileService(channel: const MethodChannel('unused')),
        reader,
      );
      expect(reader.bytes, isNull, reason: 'nothing was sent');
      expect(find.textContaining('too large'), findsOneWidget);
      expect(find.text('How to get the file'), findsOneWidget);
      expect(find.text('Add by hand'), findsOneWidget);
    });

    testWidgets('a shared photo is refused before any upload', (tester) async {
      final reader = _FakeReader();
      await openWith(
        tester,
        await transactions(tester),
        const IncomingFile(
          name: 'IMG_2001.jpg',
          path: '/nowhere.jpg',
          mimeType: 'image/jpeg',
        ),
        IncomingFileService(channel: const MethodChannel('unused')),
        reader,
      );
      expect(reader.bytes, isNull);
      expect(find.textContaining('not a statement file'), findsOneWidget);
    });
  });

  group('statement rows', () {
    test('a title that is too long for the server is shortened', () {
      final entry = StatementEntry.tryFromJson(<String, dynamic>{
        'occurred_at': '2025-01-20 10:00:00',
        'description': 'X' * 260,
        'amount': 10,
        'type': 'expense',
      })!;
      expect(entry.title.length, StatementEntry.maxTitleLength);
      expect(entry.title, endsWith('…'));
      final blank = StatementEntry.tryFromJson(<String, dynamic>{
        'occurred_at': '2025-01-20 10:00:00',
        'description': '   ',
        'amount': 10,
        'type': 'expense',
      })!;
      expect(blank.title, 'Statement entry');
    });

    test('a Bikram Sambat date is converted with the app\'s calendar', () {
      final entry = StatementEntry.tryFromJson(<String, dynamic>{
        'occurred_at': '2081-10-05 08:30:00',
        'calendar': 'bs',
        'description': 'Khaja',
        'amount': 250,
        'type': 'expense',
      })!;
      final bs = NepaliDateService().toBs(entry.occurredAt);
      expect(<int>[bs.year, bs.month, bs.day], <int>[2081, 10, 5]);
      expect(entry.occurredAt.hour, 8);
      // A day that is not on the calendar is not imported under a guess.
      final result = StatementParseResult.fromJson(<String, dynamic>{
        'entries': <Map<String, dynamic>>[
          <String, dynamic>{
            'occurred_at': '2081-13-40 00:00:00',
            'calendar': 'bs',
            'description': 'Nope',
            'amount': 1,
            'type': 'expense',
          },
        ],
      });
      expect(result.entries, isEmpty);
      expect(result.skipped.single.reason, 'Date not recognised');
    });

    test('Khalti rows are Khalti payments; a flagged row starts unticked', () {
      final result = StatementParseResult.fromJson(<String, dynamic>{
        'source': 'khalti',
        'entries': <Map<String, dynamic>>[
          <String, dynamic>{
            'occurred_at': '2025-03-02 10:15:00',
            'description': 'Mobile Topup',
            'amount': 100,
            'type': 'expense',
            'method': 'khalti',
            'check': 'Does not match the running balance on the statement',
          },
        ],
      });
      final entry = result.entries.single;
      expect(result.source, StatementSource.khalti);
      expect(entry.paymentMethod.code, 'khalti');
      expect(entry.warning, isNotNull);
      expect(entry.selected, isFalse);
      expect(result.warningCount, 1);
    });
  });

  group('More page', () {
    Future<List<String>> tapEverything(
      WidgetTester tester, {
      bool guest = false,
    }) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final opened = <String>[];
      final updates = UpdateProvider(service: _Updates());
      await updates.refresh();
      await tester.pumpWidget(
        MultiProvider(
          providers: <InheritedProvider<dynamic>>[
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
            ChangeNotifierProvider<UpdateProvider>.value(value: updates),
            Provider<BiometricService>(create: (_) => BiometricService()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: MoreScreen()),
            onGenerateRoute: (settings) {
              opened.add(settings.name!);
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const Scaffold(body: Text('opened')),
              );
            },
          ),
        ),
      );
      await tester.pump();
      for (final key in <String>[
        'more-account',
        'more-budgets',
        'more-goals',
        'more-wallets',
        'more-reports',
        'more-calendar',
        'more-import',
        'more-calculator',
        'more-settings',
        'more-backup',
        'more-help',
        'more-about',
      ]) {
        await tester.tap(find.byKey(ValueKey<String>(key)));
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.text('opened'))).pop();
        await tester.pumpAndSettle();
      }
      return opened;
    }

    testWidgets('every row opens the page it names', (tester) async {
      final opened = await tapEverything(tester);
      expect(opened, <String>[
        RoutePaths.profile,
        RoutePaths.budgets,
        RoutePaths.goals,
        RoutePaths.wallets,
        RoutePaths.reports,
        RoutePaths.festivals,
        RoutePaths.statementImport,
        RoutePaths.calculator,
        RoutePaths.settings,
        RoutePaths.backup,
        RoutePaths.help,
        RoutePaths.about,
      ]);
      expect(opened.every(RoutePaths.isKnown), isTrue);
    });

    testWidgets('groups are labelled and an update is pointed out', (
      tester,
    ) async {
      await tapEverything(tester);
      for (final label in <String>['PROFILE', 'PLAN & TRACK', 'TOOLS', 'APP']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Update'), findsOneWidget);
      expect(find.textContaining('9.9.9 is out'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
    });

    testWidgets('the profile page has the picture and the details', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: <InheritedProvider<dynamic>>[
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: KharchaApp.pageFor(RoutePaths.profile, null),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Profile'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('profile-photo')),
        findsOneWidget,
      );
      expect(find.text('Change photo'), findsOneWidget);
      expect(find.text('Full Name'), findsOneWidget);
    });

    test('every named route the app knows has a screen behind it', () {
      for (final route in RoutePaths.all) {
        expect(
          KharchaApp.pageFor(route, 'an-id'),
          isNotNull,
          reason: '$route has no case in the route table',
        );
      }
      expect(KharchaApp.pageFor('/not-a-route', null), isNull);
    });
  });
}
