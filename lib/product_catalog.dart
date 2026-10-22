import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'part.dart';

import 'package:shared_preferences/shared_preferences.dart';

const categories = [
  'Drivetrain',
  'Brakes',
  'Wheels & tyres',
  'Cockpit',
  'Tools',
  'Consumables',
  'Electrics',
  'Suspension',
  'Other',
];

const _customCatalogKey = 'custom_product_catalog_v1';

Future<List<Part>> loadProductCatalog() async {
  final data = jsonDecode(
    await rootBundle.loadString('assets/product_catalog.json'),
  ) as List;
  final bundled = data
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
  final prefs = await SharedPreferences.getInstance();
  final custom = jsonDecode(prefs.getString(_customCatalogKey) ?? '[]') as List;
  return [...bundled, ...custom.map((row) => Part.fromJson(row))];
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
  late Future<List<Part>> catalog = loadProductCatalog();
  String query = '';

  Future<void> createProduct() async {
    final products = await catalog;
    if (!mounted) return;
    final created = await Navigator.of(context).push<Part>(
      MaterialPageRoute(builder: (_) => _NewProductPage(products: products)),
    );
    if (created == null || !mounted) return;
    setState(() {
      catalog = loadProductCatalog();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Product catalog')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: createProduct,
      icon: const Icon(Icons.add),
      label: const Text('New product'),
    ),
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
                padding: const EdgeInsets.only(bottom: 88),
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

class _NewProductPage extends StatefulWidget {
  const _NewProductPage({required this.products});
  final List<Part> products;

  @override
  State<_NewProductPage> createState() => _NewProductPageState();
}

class _NewProductPageState extends State<_NewProductPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final sku = TextEditingController();
  String category = categories.first;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    sku.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final custom =
          jsonDecode(prefs.getString(_customCatalogKey) ?? '[]') as List;
      final product = Part(
        id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
        name: name.text.trim(),
        sku: sku.text.trim(),
        category: category,
      );
      final saved = await prefs.setString(
        _customCatalogKey,
        jsonEncode([...custom, product.toJson()]),
      );
      if (!saved) throw StateError('Could not save product');
      if (mounted) Navigator.pop(context, product);
    } catch (_) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save product. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New product')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Product name'),
            textCapitalization: TextCapitalization.sentences,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a product name'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: sku,
            decoration: const InputDecoration(labelText: 'SKU'),
            validator: (value) {
              final code = value?.trim() ?? '';
              if (code.isEmpty) return 'Enter a SKU';
              if (widget.products.any(
                (p) => p.sku.toLowerCase() == code.toLowerCase(),
              )) {
                return 'This SKU is already in the catalog';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (value) => setState(() => category = value!),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: saving ? null : save,
            icon: const Icon(Icons.save_outlined),
            label: Text(saving ? 'Saving…' : 'Save product'),
          ),
        ],
      ),
    ),
  );
}
