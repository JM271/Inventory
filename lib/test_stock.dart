import 'part.dart';

// Explicitly labelled sample stock; existing SKUs are never changed.
List<Part> addTestStock(List<Part> existing, List<Part> catalog) {
  const quantities = {
    'OXV8-01E': 4,
    'OXV8-07': 1,
    'OXV8-16': 8,
    'OXV8-30': 3,
    'KD001': 0,
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
          imageAsset: product.imageAsset,
          location: 'TEST · Demo shelf',
          quantity: quantities[product.sku]!,
        ),
  ];
}
