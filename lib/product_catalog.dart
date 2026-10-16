import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'part.dart';

Future<List<Part>> loadProductCatalog() async {
  final data = jsonDecode(
    await rootBundle.loadString('assets/product_catalog.json'),
  ) as List;
  return data
      .map(
        (row) => Part(
          id: 'catalog-${row['sku']}',
          name: row['name'],
          category: row['category'],
          sku: row['sku'],
          imageAsset: row['imageAsset'],
        ),
      )
      .toList();
}

class ProductPhoto extends StatelessWidget {
  const ProductPhoto({super.key, required this.part, this.size = 64});
  final Part part;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: part.imageAsset.isEmpty
        ? const Icon(Icons.inventory_2_outlined)
        : Image.asset(
            part.imageAsset,
            fit: BoxFit.contain,
            errorBuilder: (_, error, stack) =>
                const Icon(Icons.broken_image_outlined),
          ),
  );
}

class ProductCatalogPage extends StatefulWidget {
  const ProductCatalogPage({super.key});
  @override
  State<ProductCatalogPage> createState() => _ProductCatalogPageState();
}

class _ProductCatalogPageState extends State<ProductCatalogPage> {
  late final Future<List<Part>> catalog = loadProductCatalog();
  String query = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Product catalog')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Search product or SKU',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => query = value.toLowerCase()),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Part>>(
            future: catalog,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    'Could not load the product catalog. Close and reopen it to retry.',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final products = snapshot.data!
                  .where(
                    (p) => '${p.name} ${p.sku} ${p.category}'
                        .toLowerCase()
                        .contains(query),
                  )
                  .toList();
              if (products.isEmpty) {
                return const Center(child: Text('No matching products'));
              }
              return ListView.builder(
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final p = products[index];
                  return ListTile(
                    leading: ProductPhoto(part: p),
                    title: Text(
                      p.sku,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(p.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, p),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
