import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/cloud_inventory.dart';
import 'package:inventory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpInventory(WidgetTester tester, CloudInventory store) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CloudInventoryScope(
          store: store,
          child: InventoryPage(cloud: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<CloudInventory> stockedStore() async {
    final store = CloudInventory(FakeFirebaseFirestore(), 'alice');
    await store.products.doc('a').set({
      'sku': 'MS-SP-1002',
      'name': 'Chain',
      'category': 'Spare Parts',
      'priceCents': 4990,
    });
    // A catalogue product without a bexio price yet.
    await store.products.doc('b').set({
      'sku': 'OXV8-08',
      'name': 'Tail light',
      'category': 'Spare Parts',
      'priceCents': 0,
    });
    await store.partPrices.doc('b').set({'sku': 'OXV8-08', 'priceCents': 2490});
    // The catalogue price wins over a saved one.
    await store.partPrices.doc('a').set({
      'sku': 'MS-SP-1002',
      'priceCents': 100,
    });
    await store.savePart(
      Part(id: '1', name: 'Chain', category: 'Drivetrain', sku: 'ms-sp-1002'),
    );
    await store.savePart(
      Part(id: '2', name: 'Tail light', category: 'Lights', sku: 'OXV8-08'),
    );
    await store.savePart(Part(id: '3', name: 'Toolkit', category: 'Tools'));
    return store;
  }

  testWidgets('parts show the catalogue price or the saved price', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpInventory(tester, await stockedStore());
    expect(find.textContaining('CHF 49.90'), findsOneWidget);
    expect(find.textContaining('CHF 24.90'), findsOneWidget);
    expect(find.textContaining('CHF 1.00'), findsNothing);
    expect(find.textContaining('CHF'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the names list shows the price next to the stock', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'names_only_view': true});
    await pumpInventory(tester, await stockedStore());
    expect(find.text('CHF 49.90'), findsOneWidget);
    expect(find.text('CHF 24.90'), findsOneWidget);
    expect(find.textContaining('CHF'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
