import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/cloud_inventory.dart';
import 'package:inventory/main.dart';
import 'package:inventory/product_catalog.dart' show loadProductCatalog;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'shared stock ignores local V1 data and receives remote changes',
    (tester) async {
      final local = Part(
        id: 'local',
        name: 'Local private item',
        category: 'Tools',
      );
      SharedPreferences.setMockInitialValues({
        'workshop_parts': jsonEncode([local.toJson()]),
      });
      final db = FakeFirebaseFirestore();
      final store = CloudInventory(db, 'alice');
      final shared = Part(
        id: 'shared',
        name: 'Shared chain',
        category: 'Drivetrain',
        quantity: 3,
      );
      await store.savePart(shared);
      await tester.pumpWidget(
        MaterialApp(
          home: CloudInventoryScope(
            store: store,
            child: InventoryPage(cloud: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shared chain'), findsOneWidget);
      expect(find.text('Local private item'), findsNothing);
      await CloudInventory(db, 'bob').adjust(shared.id, StockSite.car, 2);
      await tester.pumpAndSettle();
      expect(find.text('Gesamt: 5'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString('workshop_parts'),
        jsonEncode([local.toJson()]),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('shared catalog excludes private local catalog products', () async {
    final local = Part(
      id: 'local',
      name: 'Private catalog item',
      category: 'Tools',
      sku: 'PRIVATE',
    );
    SharedPreferences.setMockInitialValues({
      'custom_product_catalog_v1': jsonEncode([local.toJson()]),
    });
    final store = CloudInventory(FakeFirebaseFirestore(), 'alice');
    await store.saveCatalogProduct(
      Part(
        id: 'shared',
        name: 'Shared catalog item',
        category: 'Tools',
        sku: 'SHARED',
      ),
    );
    final catalog = await loadProductCatalog(cloud: store);
    expect(catalog.any((p) => p.sku == 'PRIVATE'), false);
    expect(catalog.any((p) => p.sku == 'SHARED'), true);
  });
}
