import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/main.dart';
import 'package:inventory/product_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('all catalog products have unique SKUs and bundled photos', (
    tester,
  ) async {
    final products = await loadProductCatalog();
    expect(products.length, 243);
    expect(products.map((p) => p.sku).toSet().length, 243);
    for (final p in products) {
      expect(p.name, isNotEmpty);
      expect(categories, contains(p.category));
      if (p.imageAsset.isNotEmpty) {
        expect(
          (await rootBundle.load(p.imageAsset)).lengthInBytes,
          greaterThan(0),
        );
      }
    }
    final old = products.first.toJson()..remove('imageAsset');
    expect(Part.fromJson(old).imageAsset, isEmpty);
  });

  testWidgets('catalog selection preserves photo and quantity after reload', (
    tester,
  ) async {
    await tester.runAsync(() async {
      rootBundle.evict('assets/product_catalog.json');
      await loadProductCatalog();
    });
    SharedPreferences.setMockInitialValues({'test_stock_added_v1': true});
    await tester.pumpWidget(const InventoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aus Katalog wählen'));
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'OXV8-01E');
    await tester.pumpAndSettle();
    await tester.tap(find.text('OXV8-01E').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Quantity'), '4');
    await tester.ensureVisible(find.text('Save part'));
    await tester.tap(find.text('Save part'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const InventoryApp());
    await tester.pumpAndSettle();
    expect(find.text('V8 battery lock'), findsOneWidget);
    expect(find.text('4'), findsWidgets);
    expect(find.byType(ProductPhoto), findsOneWidget);
    // Selecting an existing SKU edits its stock rather than duplicating it.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aus Katalog wählen'));
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'OXV8-01E');
    await tester.pumpAndSettle();
    await tester.tap(find.text('OXV8-01E').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '4'), findsOneWidget);
  });
}
