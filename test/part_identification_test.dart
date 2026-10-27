import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/part.dart';

void main() {
  test('legacy supplier SKU resolves both numbers without changing stock', () {
    final part = Part(
      id: 'saved-part',
      name: 'Switch',
      category: 'Electrics',
      sku: 'OXV8-05',
      quantity: 7,
      minimum: 3,
      carQuantity: 2,
      carMinimum: 1,
      location: 'Shelf B',
      imageAsset: 'switch.jpg',
    );
    final legacy = part.toJson()
      ..remove('productNumber')
      ..remove('orderNumber');
    final restored = Part.fromJson(legacy);
    expect(restored.productIdentification, 'MS-SP-3009');
    expect(restored.supplierOrderNumber, 'OXV8-05');
    expect(restored.id, 'saved-part');
    expect(restored.sku, 'OXV8-05');
    expect(restored.quantity, 7);
    expect(restored.minimum, 3);
    expect(restored.carQuantity, 2);
    expect(restored.carMinimum, 1);
    expect(restored.location, 'Shelf B');
    expect(restored.imageAsset, 'switch.jpg');
    expect(
      Part.fromJson(restored.toJson()).productIdentification,
      'MS-SP-3009',
    );
  });

  test('unmapped or ambiguous supplier codes do not invent an internal ID', () {
    for (final sku in ['OXV8-02', 'OXV8-01E']) {
      final part = Part(id: '1', name: 'Part', category: 'Other', sku: sku);
      expect(part.productIdentification, isEmpty);
      expect(part.supplierOrderNumber, sku);
    }
  });

  test(
    'explicit edits including blanks override legacy mappings after reload',
    () {
      final part = Part(
        id: '1',
        name: 'Switch',
        category: 'Electrics',
        sku: 'OXV8-05',
        productNumber: '00123',
        orderNumber: '000987',
      );
      final restored = Part.fromJson(part.toJson());
      expect(restored.productIdentification, '00123');
      expect(restored.supplierOrderNumber, '000987');
      restored.productNumber = '';
      restored.orderNumber = '';
      final cleared = Part.fromJson(restored.toJson());
      expect(cleared.productIdentification, isEmpty);
      expect(cleared.supplierOrderNumber, isEmpty);
    },
  );

  test(
    'early dual-number records still resolve legacy empty supplier fields',
    () {
      final legacy =
          Part(
              id: '1',
              name: 'Switch',
              category: 'Electrics',
              sku: 'OXV8-05',
            ).toJson()
            ..remove('productNumber')
            ..['orderNumber'] = '';
      expect(Part.fromJson(legacy).productIdentification, 'MS-SP-3009');
      expect(Part.fromJson(legacy).supplierOrderNumber, 'OXV8-05');
    },
  );

  test(
    'both identifiers survive persistence and old records stay compatible',
    () {
      final part = Part(
        id: '1',
        name: 'Brake',
        category: 'Brakes',
        sku: '00123',
        orderNumber: '000987',
      );
      final restored = Part.fromJson(part.toJson());
      expect(restored.sku, '00123');
      expect(restored.productIdentification, '00123');
      expect(restored.orderNumber, '000987');
      final legacy = part.toJson()..remove('orderNumber');
      expect(Part.fromJson(legacy).orderNumber, '');
    },
  );
}
