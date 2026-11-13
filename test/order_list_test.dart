import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/cloud_inventory.dart';
import 'package:inventory/inventory_pdf.dart';
import 'package:inventory/order_list.dart';
import 'package:inventory/product_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_fixture.dart';

void main() {
  testWidgets('products are marked in the catalog and listed to order', (
    tester,
  ) async {
    // A phone: the rows must fit without overflowing.
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(withCatalog());
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    Future<void> settle() async {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(const MaterialApp(home: ProductCatalogPage()));
    await settle();

    // The first product is MS-SP-3009, ordered as OXV8-05.
    await tester.tap(find.text('Order').first);
    await settle();
    expect(find.byTooltip('Remove from order list'), findsOneWidget);
    await tester.tap(find.byTooltip('Order more'));
    await settle();
    expect(find.byTooltip('Order less'), findsOneWidget);

    // Type the quantity instead of tapping + many times.
    await tester.tap(find.byTooltip('Enter quantity'));
    await settle();
    await tester.enterText(find.byType(TextFormField), '25');
    await tester.tap(find.text('OK'));
    await settle();
    expect(find.text('25'), findsOneWidget);

    await tester.tap(find.byTooltip('Order list'));
    await settle();
    expect(find.text('1 products · 25 pieces'), findsOneWidget);
    expect(find.text('OXV8-05'), findsOneWidget);
    expect(find.text('3 in 1 switch'), findsOneWidget);
    expect(find.text('Our ID: MS-SP-3009'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy as text'));
    await settle();
    expect(copied, 'OXV8-05\t25\t3 in 1 switch');

    await tester.tap(find.byTooltip('Empty the order list'));
    await settle();
    await tester.tap(find.text('Empty list'));
    await settle();
    expect(find.textContaining('Nothing to order yet'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('order_list_v1')!), isEmpty);

    // Back in the catalog the product is no longer marked.
    await tester.pageBack();
    await settle();
    expect(find.byTooltip('Remove from order list'), findsNothing);
  });

  test('the order list is shared through the database', () async {
    final db = FakeFirebaseFirestore();
    final cloud = CloudInventory(db, 'alice');
    final orders = OrderList(cloud);
    addTearDown(orders.dispose);

    await orders.setQuantity('oxv8-08', 3);
    await orders.setQuantity('MS-SP-3009', 2);
    await Future<void>.delayed(Duration.zero);
    expect(orders.quantityOf('OXV8-08'), 3);
    final saved = await cloud.orderList
        .doc(CloudInventory.productId('OXV8-08'))
        .get();
    expect(saved.data(), {'sku': 'OXV8-08', 'quantity': 3});

    // A colleague changes the same list.
    await CloudInventory(db, 'bob').setOrderQuantity('OXV8-08', 10);
    await CloudInventory(db, 'bob').setOrderQuantity('MS-SP-3009', 0);
    await Future<void>.delayed(Duration.zero);
    expect(orders.quantities, {'OXV8-08': 10});

    // Sorted by the number to order by; a product that is not in the
    // catalogue stays on the list under its SKU.
    await orders.setQuantity('MS-SP-3010', 1);
    await Future<void>.delayed(Duration.zero);
    final lines = orders.lines(catalogFixture);
    expect(
      [for (final l in lines) '${orderNumberOf(l.product)} ×${l.quantity}'],
      ['OXV8-07 ×1', 'OXV8-08 ×10'],
    );
    expect(lines.first.product.name, 'Front Light (LED) for Fatbike');
    expect(lines.last.product.name, 'OXV8-08');

    await orders.clear();
    await Future<void>.delayed(Duration.zero);
    expect(orders.length, 0);
    expect((await cloud.orderList.get()).docs, isEmpty);
  });

  test('the order list PDF takes supplier names as they are', () async {
    final bytes = await buildOrderListPdf([
      (
        product: productPart({
          'sku': 'OXV8-02',
          'supplierSku': 'OXV8-02',
          'name': 'V8 Controller 48V 21A V3.0(Code：6305),straight valve，SV',
          'category': 'Electrics',
        }),
        quantity: 4,
      ),
      (product: catalogFixture.first, quantity: 2),
    ], DateTime.utc(2026, 11, 13));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
