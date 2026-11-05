import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/catalog_migration.dart';
import 'package:inventory/cloud_inventory.dart';
import 'package:inventory/part.dart';
import 'package:inventory/product_catalog.dart';

Part product(
  String sku,
  String name, {
  String supplier = '',
  String image = '',
}) => productPart({
  'sku': sku,
  'name': name,
  'category': 'Spare Parts',
  'supplierSku': supplier,
  'imageAsset': image,
});

void main() {
  final catalog = [
    product(
      'MS-SP-3009',
      '3 in 1 switch',
      supplier: 'OXV8-05',
      image: 'assets/products/oxv8-05.png',
    ),
    product('MS-SP-2005', 'Brake disc V8 - 160mm (1pce)', supplier: 'OXV8-17A'),
    product('MS-SP-3004', 'Controller Dapper 21A'),
    product('MS-SP-3011', 'Controller Dapper PRO 21A'),
  ];

  // Stock as saved by earlier versions: supplier SKUs from the old catalogue.
  List<Part> stock() => [
    Part(
      id: 'catalog-OXV8-05',
      name: '3 in 1 switch',
      category: 'Electrics',
      sku: 'OXV8-05',
      imageAsset: 'assets/products/oxv8-05.png',
      location: 'Shelf A',
      quantity: 3,
      minimum: 1,
      carQuantity: 1,
    ),
    // A second record of the same product, created with our number.
    Part(
      id: 'custom-1',
      name: 'Switch',
      category: 'Other',
      sku: 'MS-SP-3009',
      productNumber: 'MS-SP-3009',
      quantity: 2,
      minimum: 4,
    ),
    // Only the supplier number, and the legacy mapping knows it.
    Part(
      id: 'catalog-OXV8-17A',
      name: 'Brake disc 160mm',
      category: 'Brakes',
      sku: 'OXV8-17A',
      quantity: 5,
    ),
    // Supplier code of two products: needs a choice.
    Part(
      id: 'catalog-OXV8-02',
      name: 'V8 Controller 48V 21A',
      category: 'Electrics',
      sku: 'OXV8-02',
      quantity: 2,
    ),
    // Not in the catalogue.
    Part(
      id: 'catalog-RF-M09',
      name: 'Rearview mirror',
      category: 'Cockpit',
      sku: 'RF-M09',
      quantity: 4,
    ),
  ];

  test('suggests products by own number, then by unique supplier number', () {
    final rows = planCatalogMigration(stock(), catalog);
    String? targetOf(String id) =>
        rows.singleWhere((r) => r.part.id == id).target?.sku;
    expect(targetOf('catalog-OXV8-05'), 'MS-SP-3009');
    expect(targetOf('custom-1'), 'MS-SP-3009'); // name and category differ
    expect(targetOf('catalog-OXV8-17A'), 'MS-SP-2005');
    expect(targetOf('catalog-OXV8-02'), isNull);
    expect(targetOf('catalog-RF-M09'), isNull);
    // Parts without a product come last.
    expect(rows.last.target, isNull);
  });

  test('switching keeps every quantity and merges duplicates', () {
    final parts = stock();
    final rows = planCatalogMigration(parts, catalog);
    // The controller is the Dapper PRO one.
    rows.singleWhere((r) => r.part.id == 'catalog-OXV8-02').target = catalog
        .singleWhere((p) => p.sku == 'MS-SP-3011');
    final changes = buildCatalogMigration(rows, parts);

    final switchChange = changes.singleWhere(
      (c) => c.after?.sku == 'MS-SP-3009',
    );
    final merged = switchChange.after!;
    // The record that already had our number takes the stock.
    expect(switchChange.before.id, 'custom-1');
    expect((merged.quantity, merged.carQuantity), (5, 1));
    expect(merged.minimum, 4);
    expect(merged.location, 'Shelf A');
    expect(merged.name, '3 in 1 switch');
    expect(merged.category, 'Spare Parts');
    expect(merged.productNumber, 'MS-SP-3009');
    expect(merged.orderNumber, 'OXV8-05');
    expect(merged.imageAsset, 'assets/products/oxv8-05.png');
    expect(changes.where((c) => c.after == null).map((c) => c.before.id), [
      'catalog-OXV8-05',
    ]);

    final disc = changes
        .singleWhere((c) => c.after?.sku == 'MS-SP-2005')
        .after!;
    expect(disc.id, 'catalog-OXV8-17A');
    expect(disc.quantity, 5);
    expect(disc.orderNumber, 'OXV8-17A');
    final controller = changes
        .singleWhere((c) => c.after?.sku == 'MS-SP-3011')
        .after!;
    expect(controller.quantity, 2);
    expect(controller.orderNumber, 'OXV8-02');
    // The mirror is not touched.
    expect(changes.where((c) => c.before.id == 'catalog-RF-M09'), isEmpty);

    // Totals per site are unchanged.
    int total(Iterable<Part> ps) => ps.fold(0, (s, p) => s + p.quantity);
    final after = [
      for (final p in parts)
        if (!changes.any((c) => c.before.id == p.id)) p,
      for (final c in changes)
        if (c.after != null) c.after!,
    ];
    expect(total(after), total(parts));
  });

  test('the switch is written in one transaction with history', () async {
    final db = FakeFirebaseFirestore();
    final cloud = CloudInventory(db, 'admin');
    final parts = stock();
    for (final p in parts) {
      await cloud.parts.doc(CloudInventory.documentId(p.id)).set(p.toJson());
    }
    final rows = planCatalogMigration(parts, catalog);
    await cloud.applyPartChanges(buildCatalogMigration(rows, parts));

    final saved = [
      for (final d in (await cloud.parts.get()).docs) Part.fromJson(d.data()),
    ];
    expect(saved.map((p) => p.sku).toSet(), {
      'MS-SP-3009',
      'MS-SP-2005',
      'OXV8-02',
      'RF-M09',
    });
    expect(saved.singleWhere((p) => p.sku == 'MS-SP-3009').quantity, 5);
    final history = [
      for (final d in (await cloud.changes.get()).docs) d.data(),
    ];
    expect(history.map((c) => c['action']), containsAll(['Edited', 'Deleted']));

    // Nothing left to switch, except the parts without a product.
    final again = planCatalogMigration(saved, catalog);
    expect(again.where((r) => r.target != null), isEmpty);

    // A part changed since the preview stops the whole switch.
    final stale = planCatalogMigration(parts, catalog);
    await expectLater(
      cloud.applyPartChanges(buildCatalogMigration(stale, parts)),
      throwsA(isA<InventoryConflict>()),
    );
  });

  test('the shared catalogue is seeded once', () async {
    final db = FakeFirebaseFirestore();
    final cloud = CloudInventory(db, 'editor');
    final bundled = [
      {
        'sku': 'ms-sp-3009',
        'name': '3 in 1 switch',
        'category': 'Spare Parts',
        'supplierSku': 'OXV8-05',
        'priceCents': 4500,
      },
    ];
    expect(await cloud.seedProducts(bundled), isTrue);
    final doc = await cloud.products
        .doc(CloudInventory.productId('MS-SP-3009'))
        .get();
    expect(doc.data()!['sku'], 'MS-SP-3009');
    expect(doc.data()!['priceCents'], 4500);
    await doc.reference.delete();
    expect(await cloud.seedProducts(bundled), isFalse);
    expect((await cloud.products.get()).docs, isEmpty);

    await cloud.saveProduct({
      'sku': 'MS-SP-9001',
      'name': 'New',
      'category': 'Spare Parts',
    });
    await expectLater(
      cloud.saveProduct({
        'sku': 'MS-SP-9001',
        'name': 'Again',
        'category': 'Spare Parts',
      }),
      throwsA(isA<InventoryConflict>()),
    );
  });
}
