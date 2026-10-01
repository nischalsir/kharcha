import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/core/utils/phone_number.dart';
import 'package:kharcha_app/providers/friend_provider.dart';
import 'package:kharcha_app/providers/pasal_provider.dart';
import 'package:kharcha_app/repositories/friend_repository.dart';
import 'package:kharcha_app/repositories/pasal_repository.dart';
import 'package:kharcha_app/screens/friends/friends_screen.dart';
import 'package:kharcha_app/screens/pasal/add_pasal_screen.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/contact_picker.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:kharcha_app/widgets/common/primary_button.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A contact picker that hands back [contact], or fails with [failure].
class _FakePicker extends ContactPicker {
  _FakePicker({this.contact, this.failure});

  final PickedContact? contact;
  final ContactPickFailure? failure;
  int opened = 0;

  @override
  bool get supported => true;

  @override
  Future<PickedContact?> pickPhone() async {
    opened++;
    if (failure != null) throw failure!;
    return contact;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('phone numbers', () {
    test('are kept in one shape, however they were written', () {
      expect(PhoneNumber.normalize('9812345678'), '9812345678');
      expect(PhoneNumber.normalize(' 981-234 5678 '), '9812345678');
      expect(PhoneNumber.normalize('+977 981-2345678'), '+9779812345678');
      expect(PhoneNumber.normalize('+977 (98) 1234.5678'), '+9779812345678');
      // A second plus after the country code is only a slip of the thumb.
      expect(PhoneNumber.normalize('+977+9812345678'), '+9779812345678');
      // 00 is how a country code is dialled without a plus.
      expect(PhoneNumber.normalize('009779812345678'), '+9779812345678');
      // Nepali digits are digits.
      expect(PhoneNumber.normalize('९८१२३४५६७८'), '9812345678');
      // A landline with its area code.
      expect(PhoneNumber.normalize('(01) 4-123456'), '014123456');
    });

    test('nothing typed is no number', () {
      expect(PhoneNumber.normalize(null), isNull);
      expect(PhoneNumber.normalize('   '), isNull);
      expect(PhoneNumber.normalize('+'), isNull);
      expect(PhoneNumber.normalize('--'), isNull);
    });

    test('a believable number has between 6 and 15 digits', () {
      expect(PhoneNumber.isValid('9812345678'), isTrue);
      expect(PhoneNumber.isValid('+9779812345678'), isTrue);
      expect(PhoneNumber.isValid('014123456'), isTrue);
      expect(PhoneNumber.isValid('12345'), isFalse);
      expect(PhoneNumber.isValid('+1234567890123456'), isFalse);
    });
  });

  group('the contact picker', () {
    const channel = MethodChannel(ContactPicker.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('returns the chosen number tidied, with the name', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'pickPhone');
        return <String, String?>{
          'number': '+977 981-2345678',
          'name': ' Sita Sharma ',
        };
      });
      final contact = await ContactPicker().pickPhone();
      expect(contact!.number, '+9779812345678');
      expect(contact.name, 'Sita Sharma');
    });

    test('backing out of the picker is not an error', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await ContactPicker().pickPhone(), isNull);
    });

    test('a contact with no usable number is refused', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => <String, String?>{'number': '*#', 'name': 'Shop'},
      );
      await expectLater(
        ContactPicker().pickPhone(),
        throwsA(
          isA<ContactPickFailure>().having(
            (f) => f.reason,
            'reason',
            'no_number',
          ),
        ),
      );
    });

    test('a phone with no contacts app says so', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'no_app'),
      );
      await expectLater(
        ContactPicker().pickPhone(),
        throwsA(
          isA<ContactPickFailure>().having((f) => f.reason, 'reason', 'no_app'),
        ),
      );
    });
  });

  group('forms', () {
    late SyncService sync;
    late CacheService cache;
    final real = ContactPicker.instance;
    tearDown(() => ContactPicker.instance = real);

    Future<void> services(WidgetTester tester) async {
      tester.view.physicalSize = const Size(440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => <String>['wifi'],
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
        (call) async => null,
      );
      await tester.runAsync(() async {
        cache = await CacheService.create();
        sync = SyncService(cache: cache, remote: SupabaseService());
      });
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      sync.dispose();
    }

    Future<PasalRepository> openPasal(WidgetTester tester) async {
      await services(tester);
      final dates = NepaliDateService();
      final repository = PasalRepository(cache, sync);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>.value(value: dates),
            ChangeNotifierProvider<PasalProvider>(
              create: (_) => PasalProvider(
                cache: cache,
                repository: repository,
                dates: dates,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const AddPasalScreen(),
          ),
        ),
      );
      await tester.pump();
      return repository;
    }

    Future<void> save(WidgetTester tester, String button) async {
      await tester.runAsync(() async {
        // The page title says the same as its button: press the button.
        await tester.tap(find.widgetWithText(PrimaryButton, button));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
    }

    testWidgets('pasal: the contacts icon fills the phone and the owner', (
      tester,
    ) async {
      final picker = _FakePicker(
        contact: const PickedContact(
          number: '+9779812345678',
          name: 'Ram Bahadur',
        ),
      );
      ContactPicker.instance = picker;
      final repository = await openPasal(tester);

      await tester.tap(find.byIcon(Icons.contacts_rounded));
      await tester.pump();
      expect(picker.opened, 1);
      expect(find.text('+9779812345678'), findsOneWidget);
      expect(find.text('Ram Bahadur'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'Corner shop');
      await save(tester, 'Add Pasal');
      final saved = repository.pasals().single;
      expect(saved.phone, '+9779812345678');
      expect(saved.ownerName, 'Ram Bahadur');
      await close(tester);
    });

    testWidgets('pasal: a typed +977+98… number is saved tidied', (
      tester,
    ) async {
      ContactPicker.instance = _FakePicker();
      final repository = await openPasal(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Corner shop');
      await tester.enterText(
        find.byType(TextFormField).at(2),
        '+977+9812345678',
      );
      await save(tester, 'Add Pasal');
      expect(repository.pasals().single.phone, '+9779812345678');
      await close(tester);
    });

    testWidgets('pasal: something that is not a number is not saved', (
      tester,
    ) async {
      ContactPicker.instance = _FakePicker();
      final repository = await openPasal(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Corner shop');
      await tester.enterText(find.byType(TextFormField).at(2), '123');
      await save(tester, 'Add Pasal');
      expect(find.textContaining('Enter a valid phone number'), findsOneWidget);
      expect(repository.pasals(), isEmpty);
      await close(tester);
    });

    testWidgets('pasal: a contact without a number says so', (tester) async {
      ContactPicker.instance = _FakePicker(
        failure: const ContactPickFailure('no_number'),
      );
      await openPasal(tester);

      await tester.tap(find.byIcon(Icons.contacts_rounded));
      await tester.pump();
      expect(find.text('That contact has no phone number.'), findsOneWidget);
      await close(tester);
    });

    testWidgets('friend: a contact fills the name and the number', (
      tester,
    ) async {
      final picker = _FakePicker(
        contact: const PickedContact(number: '9812345678', name: 'Sita Sharma'),
      );
      ContactPicker.instance = picker;
      await services(tester);
      final repository = FriendRepository(cache, sync);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>(create: (_) => NepaliDateService()),
            ChangeNotifierProvider<FriendProvider>(
              create: (_) =>
                  FriendProvider(cache: cache, repository: repository),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showAddFriendSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.contacts_rounded));
      await tester.pump();
      expect(find.text('Sita Sharma'), findsOneWidget);
      expect(find.text('9812345678'), findsOneWidget);

      await save(tester, 'Save');
      await tester.pumpAndSettle();
      final saved = repository.friends().single;
      expect(saved.name, 'Sita Sharma');
      expect(saved.phone, '9812345678');
      await close(tester);
    });
  });
}
