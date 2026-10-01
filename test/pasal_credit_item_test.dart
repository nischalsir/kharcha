import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/theme/app_theme.dart';
import 'package:kharcha_app/models/pasal_credit_item_model.dart';
import 'package:kharcha_app/models/pasal_credit_model.dart';
import 'package:kharcha_app/models/sync_models.dart';
import 'package:kharcha_app/providers/pasal_provider.dart';
import 'package:kharcha_app/repositories/pasal_repository.dart';
import 'package:kharcha_app/screens/pasal/add_pasal_credit_screen.dart';
import 'package:kharcha_app/services/cache_service.dart';
import 'package:kharcha_app/services/nepali_date_service.dart';
import 'package:kharcha_app/services/pasal_image_store.dart';
import 'package:kharcha_app/services/supabase_service.dart';
import 'package:kharcha_app/services/sync_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _pasalId = '11111111-1111-4111-8111-111111111111';
const String _creditId = '22222222-2222-4222-8222-222222222222';
const String _itemId = '33333333-3333-4333-8333-333333333333';

/// An item row exactly as an app version before pictures wrote it.
Map<String, dynamic> _legacyRow() => <String, dynamic>{
  'id': _itemId,
  'credit_id': _creditId,
  'item_name': 'Rice',
  'quantity': 3,
  'unit': 'kg',
  'unit_price': 40,
  'sort_order': 0,
  'created_at': '2026-09-01T00:00:00Z',
  'updated_at': '2026-09-01T00:00:00Z',
  'deleted_at': null,
};

void main() {
  group('PasalCreditItem', () {
    test('a record written before pictures still reads and totals', () {
      final item = PasalCreditItem.fromJson(_legacyRow());
      expect(item.itemName, 'Rice');
      expect(item.quantity, 3);
      expect(item.unit, 'kg');
      expect(item.totalPrice, 120);
      expect(item.imagePath, isNull);
    });

    test('the picture path survives a round trip', () {
      final item = PasalCreditItem.fromJson(<String, dynamic>{
        ..._legacyRow(),
        'quantity': 1,
        'unit_price': 250,
        'image_path': 'user-1/pasal/$_itemId.jpg',
      });
      expect(item.imagePath, 'user-1/pasal/$_itemId.jpg');
      expect(item.totalPrice, 250);
      expect(PasalCreditItem.fromJson(item.toJson()).imagePath, item.imagePath);
    });

    test('an empty path counts as no picture', () {
      final item = PasalCreditItem.fromJson(<String, dynamic>{
        ..._legacyRow(),
        'image_path': '  ',
      });
      expect(item.imagePath, isNull);
    });

    test('copyWith can clear the picture as well as set it', () {
      final item = PasalCreditItem.fromJson(<String, dynamic>{
        ..._legacyRow(),
        'image_path': 'u/pasal/x.jpg',
      });
      expect(item.copyWith(itemName: 'Dal').imagePath, 'u/pasal/x.jpg');
      expect(item.copyWith(imagePath: () => null).imagePath, isNull);
    });

    test('the column is sent to the server, the computed total is not', () {
      final remote = SyncEntity.pasalCreditItems.toRemote(<String, dynamic>{
        ...PasalCreditItem.fromJson(_legacyRow()).toJson(),
        'total_price': 120,
      }, 'user-1');
      expect(remote.containsKey('image_path'), isTrue);
      expect(remote.containsKey('total_price'), isFalse);
    });
  });

  test('a picture is stored in its owner’s own folder', () {
    expect(
      PasalImageStore.pathFor('user-1', _itemId),
      'user-1/pasal/$_itemId.jpg',
    );
  });

  group('Add Pasal Credit screen', () {
    late PasalProvider provider;

    setUp(() {
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
    });

    Future<void> pump(
      WidgetTester tester, {
      PasalCredit? existing,
      List<PasalCreditItem>? items,
    }) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      late CacheService cache;
      late SyncService sync;
      await tester.runAsync(() async {
        cache = await CacheService.create();
        sync = SyncService(cache: cache, remote: SupabaseService());
      });
      addTearDown(sync.dispose);
      final dates = NepaliDateService();
      provider = PasalProvider(
        cache: cache,
        repository: PasalRepository(cache, sync),
        dates: dates,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NepaliDateService>.value(value: dates),
            ChangeNotifierProvider<PasalProvider>.value(value: provider),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: AddPasalCreditScreen(
              pasalId: _pasalId,
              existing: existing,
              existingItems: items,
            ),
          ),
        ),
      );
    }

    Finder field(String label) => find.widgetWithText(TextFormField, label);

    testWidgets('an item is a name, a price and an optional picture', (
      tester,
    ) async {
      await pump(tester);

      expect(field('Item name'), findsOneWidget);
      expect(field('Price'), findsOneWidget);
      expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
      expect(find.byIcon(Icons.calculate_outlined), findsOneWidget);
      // No quantity, unit or unit price anywhere.
      expect(find.text('Qty'), findsNothing);
      expect(find.text('Unit'), findsNothing);
      expect(find.text('Unit price'), findsNothing);
    });

    testWidgets('saving one item without a picture records its price', (
      tester,
    ) async {
      await pump(tester);

      await tester.enterText(field('Purchase title'), 'Groceries');
      await tester.enterText(field('Item name'), 'Rice');
      await tester.enterText(field('Price'), '250');
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Add Credit'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      final credits = provider.creditsFor(_pasalId);
      expect(credits, hasLength(1));
      expect(credits.single.totalAmount, 250);
      final items = provider.itemsFor(credits.single.id);
      expect(items.single.itemName, 'Rice');
      expect(items.single.quantity, 1);
      expect(items.single.unitPrice, 250);
      expect(items.single.totalPrice, 250);
      expect(items.single.imagePath, isNull);
    });

    testWidgets('several items add up', (tester) async {
      await pump(tester);

      await tester.enterText(field('Purchase title'), 'Groceries');
      await tester.enterText(field('Item name'), 'Rice');
      await tester.enterText(field('Price'), '250');
      await tester.tap(find.text('Add item'));
      await tester.pump();
      await tester.enterText(field('Item name').last, 'Dal');
      await tester.enterText(field('Price').last, '100');
      await tester.pump();

      expect(find.textContaining('350'), findsOneWidget);
    });

    testWidgets('an item with a name but no price is not saved', (
      tester,
    ) async {
      await pump(tester);

      await tester.enterText(field('Purchase title'), 'Groceries');
      await tester.enterText(field('Item name'), 'Rice');
      await tester.tap(find.text('Add Credit'));
      await tester.pump();

      expect(find.text('Enter an amount'), findsOneWidget);
      expect(provider.creditsFor(_pasalId), isEmpty);
    });

    testWidgets('an old quantity x price item opens as one price', (
      tester,
    ) async {
      final now = DateTime(2026, 9, 1);
      await pump(
        tester,
        existing: PasalCredit(
          id: _creditId,
          pasalId: _pasalId,
          title: 'Groceries',
          purchaseDate: now,
          totalAmount: 120,
          paidAmount: 0,
          status: PasalCreditStatus.unpaid,
          createdAt: now,
          updatedAt: now,
        ),
        items: <PasalCreditItem>[PasalCreditItem.fromJson(_legacyRow())],
      );

      // 3 kg at 40 was 120, and still is.
      expect(find.widgetWithText(TextFormField, '120'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Rice'), findsOneWidget);
      expect(find.textContaining('120'), findsWidgets);
    });

    testWidgets('the calculator fills the price', (tester) async {
      await pump(tester);

      await tester.tap(find.byIcon(Icons.calculate_outlined));
      await tester.pumpAndSettle();
      for (final key in '100+250'.split('')) {
        await tester.tap(find.text(key).last);
        await tester.pump();
      }
      await tester.tap(find.text('Use 350'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, '350'), findsOneWidget);
    });
  });
}
