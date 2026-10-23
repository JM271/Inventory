import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/cloud_inventory.dart';
import 'package:inventory/part.dart';

Part sample({int quantity = 5, int car = 1}) => Part(
  id: 'part/with/slashes',
  name: 'Chain',
  category: 'Drivetrain',
  sku: 'CHAIN',
  quantity: quantity,
  carQuantity: car,
);

void main() {
  late FakeFirebaseFirestore db;
  late CloudInventory first;
  late CloudInventory second;
  setUp(() {
    db = FakeFirebaseFirestore();
    first = CloudInventory(db, 'alice');
    second = CloudInventory(db, 'bob');
  });
  Future<Part> current() async => Part.fromJson(
    (await first.parts.doc(CloudInventory.documentId(sample().id)).get())
        .data()!,
  );

  test(
    'two clients read the same stock and deltas use latest quantity',
    () async {
      await first.savePart(sample());
      await first.adjust(sample().id, StockSite.workshop, -1);
      await second.adjust(sample().id, StockSite.workshop, -1);
      expect((await current()).quantity, 3);
      expect((await second.parts.get()).docs.single.data()['quantity'], 3);
      expect((await first.workshop.get()).data()?['initialized'], true);
    },
  );

  test(
    'transfer is atomic and excessive removal leaves both sites intact',
    () async {
      await first.savePart(sample());
      await second.transfer(sample().id, StockSite.workshop, 3);
      expect((await current()).quantity, 2);
      expect((await current()).carQuantity, 4);
      await expectLater(
        first.transfer(sample().id, StockSite.workshop, 3),
        throwsArgumentError,
      );
      expect((await current()).totalQuantity, 6);
      expect((await current()).quantity, 2);
    },
  );

  test(
    'stale editor and deletion cannot overwrite a concurrent booking',
    () async {
      final original = sample();
      await first.savePart(original);
      await second.adjust(original.id, StockSite.car, 1);
      final edited = Part.fromJson(original.toJson())..name = 'Renamed';
      await expectLater(
        first.savePart(edited, expected: original),
        throwsA(isA<InventoryConflict>()),
      );
      await expectLater(
        first.deletePart(original),
        throwsA(isA<InventoryConflict>()),
      );
      expect((await current()).name, 'Chain');
      expect((await current()).carQuantity, 2);
    },
  );

  test(
    'deleted items are not recreated by a stale adjustment/editor',
    () async {
      await first.savePart(sample());
      await second.deletePart(sample());
      await expectLater(
        first.adjust(sample().id, StockSite.car, 1),
        throwsA(isA<InventoryConflict>()),
      );
      await expectLater(
        first.savePart(sample(), expected: sample()),
        throwsA(isA<InventoryConflict>()),
      );
      expect((await first.parts.get()).docs, isEmpty);
    },
  );

  test(
    'local import works once and cannot overwrite a used but empty warehouse',
    () async {
      await first.importLocal([sample()]);
      await second.deletePart(sample());
      await expectLater(
        second.importLocal([sample(quantity: 99)]),
        throwsA(isA<InventoryConflict>()),
      );
      expect((await first.parts.get()).docs, isEmpty);
    },
  );

  test(
    'local import includes custom catalog and aborts entirely on SKU conflict',
    () async {
      final custom = sample();
      await first.saveCatalogProduct(custom);
      await expectLater(
        first.importLocal([sample()], custom: [sample()..name = 'Different']),
        throwsA(isA<InventoryConflict>()),
      );
      expect((await first.parts.get()).docs, isEmpty);
      expect((await first.workshop.get()).exists, false);
      await first.importLocal([sample()], custom: [custom]);
      expect((await first.parts.get()).docs, hasLength(1));
      expect((await first.catalog.get()).docs, hasLength(1));
    },
  );

  test('creating an existing ID is a conflict', () async {
    await first.savePart(sample());
    await expectLater(
      second.savePart(sample(quantity: 99)),
      throwsA(isA<InventoryConflict>()),
    );
    expect((await current()).quantity, 5);
  });

  test('custom catalog rejects case-insensitive duplicate SKU', () async {
    await first.saveCatalogProduct(sample());
    await expectLater(
      second.saveCatalogProduct(sample()..sku = ' chain '),
      throwsA(isA<InventoryConflict>()),
    );
    expect((await first.catalog.get()).docs, hasLength(1));
  });
}
