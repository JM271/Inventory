import 'dart:convert';

import 'package:inventory/part.dart';
import 'package:inventory/product_catalog.dart';

/// Catalogue products for tests. The real catalogue lives only in the
/// database; without Firebase the app knows just the products stored on the
/// device, so tests put these there.
final catalogFixture = [
  for (final row in const [
    {
      'sku': 'MS-SP-3009',
      'supplierSku': 'OXV8-05',
      'name': '3 in 1 switch',
      'category': 'Spare Parts',
      'imageAsset': 'assets/products/oxv8-05.png',
    },
    {
      'sku': 'MS-SP-3010',
      'supplierSku': 'OXV8-07',
      'name': 'Front Light (LED) for Fatbike',
      'category': 'Spare Parts',
      'imageAsset': 'assets/products/oxv8-07.png',
    },
    {
      'sku': 'MS-SP-2007',
      'name': 'Brake pad for hydraulic disc (pair)',
      'category': 'Spare Parts',
      'imageAsset': 'assets/products/m-30e.png',
    },
    {
      'sku': 'MS-SP-2002',
      'supplierSku': 'OXV8-30',
      'name': 'Chain for Fatbike',
      'category': 'Spare Parts',
      'imageAsset': 'assets/products/oxv8-30.png',
    },
    {
      'sku': 'MS-SP-1001',
      'name': 'Kenda Krusade Fatbike tire 20"x4"',
      'category': 'Spare Parts',
      'imageAsset': 'assets/products/kd001.png',
    },
  ])
    productPart(row),
];

/// Shared preferences holding [catalogFixture] as this device's catalogue.
Map<String, Object> withCatalog([Map<String, Object> values = const {}]) => {
  ...values,
  'custom_product_catalog_v1': jsonEncode([
    for (final Part p in catalogFixture) p.toJson(),
  ]),
};
