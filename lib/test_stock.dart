import 'part.dart';

// Explicitly labelled sample stock; existing SKUs are never changed.
List<Part> addTestStock(List<Part> existing, List<Part> catalog) {
  const quantities = {
    'MS-SP-3009': 4,
    'MS-SP-3010': 1,
    'MS-SP-2007': 8,
    'MS-SP-2002': 3,
    'MS-SP-1001': 0,
  };
  final skus = existing.map((p) => p.sku.toUpperCase()).toSet();
  return [
    ...existing,
    for (final product in catalog)
      if (quantities.containsKey(product.sku) && !skus.contains(product.sku))
        Part(
          id: 'test-${product.sku}',
          name: '${product.name} [TEST]',
          category: product.category,
          sku: product.sku,
          productNumber: product.productIdentification,
          orderNumber: product.supplierOrderNumber,
          imageAsset: product.imageAsset,
          location: 'TEST · Demo shelf',
          quantity: quantities[product.sku]!,
        ),
  ];
}
