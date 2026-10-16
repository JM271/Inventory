import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/part.dart';
import 'package:inventory/test_stock.dart';

void main() {
  test('test stock keeps existing quantities and does not duplicate SKUs', () {
    final existing = Part(
      id: 'mine',
      name: 'My chain',
      category: 'Drivetrain',
      sku: 'oxv8-30',
      quantity: 17,
    );
    final catalog = [
      for (final sku in ['OXV8-30', 'OXV8-07', 'OXV8-16', 'KD001', 'OXV8-01E'])
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
    expect(result.singleWhere((p) => p.sku == 'KD001').quantity, 0);
    expect(addTestStock(result, catalog).length, 5);
  });
}
