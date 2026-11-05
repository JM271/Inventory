import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/part.dart';
import 'package:inventory/test_stock.dart';

void main() {
  test('test stock keeps existing quantities and does not duplicate SKUs', () {
    final existing = Part(
      id: 'mine',
      name: 'My chain',
      category: 'Drivetrain',
      sku: 'ms-sp-2002',
      quantity: 17,
    );
    final catalog = [
      for (final sku in [
        'MS-SP-2002',
        'MS-SP-3010',
        'MS-SP-2007',
        'MS-SP-1001',
        'MS-SP-3009',
      ])
        Part(
          id: sku,
          name: sku,
          category: 'Other',
          sku: sku,
          imageAsset: 'assets/products/$sku.png',
        ),
    ];
    final result = addTestStock([existing], catalog);
    expect(result.length, 5);
    expect(result.first, same(existing));
    expect(existing.quantity, 17);
    expect(
      result
          .skip(1)
          .every((p) => p.name.endsWith('[TEST]') && p.imageAsset.isNotEmpty),
      isTrue,
    );
    expect(result.singleWhere((p) => p.sku == 'MS-SP-1001').quantity, 0);
    expect(addTestStock(result, catalog).length, 5);
  });
}
