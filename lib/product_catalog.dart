import 'dart:async';

import 'cloud_inventory.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'order_list.dart';
import 'part.dart';
import 'product_images.dart';

import 'package:shared_preferences/shared_preferences.dart';

const categories = [
  'Fatbikes',
  'Spare Parts',
  'Accessoires',
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

/// A product of the shared catalogue as a template for a stock part: our
/// product ID is the SKU, the supplier number the order number. A supplier
/// product without a product ID of ours is stored under its supplier number
/// (SKU and supplier number are the same) and has no product ID.
Part productPart(Map<String, dynamic> row) {
  final sku = (row['sku'] as String? ?? '').trim().toUpperCase();
  final supplier = (row['supplierSku'] as String? ?? '').trim();
  return Part(
    id: 'catalog-$sku',
    name: (row['name'] as String? ?? '').trim(),
    category: (row['category'] as String? ?? '').trim(),
    sku: sku,
    productNumber: supplier.toUpperCase() == sku ? '' : sku,
    orderNumber: supplier,
    imageAsset: (row['imageAsset'] as String? ?? '').trim(),
  );
}

/// The shared product catalogue: the products in the database (kept in sync
/// with bexio by tool/bexio_sync) plus products added in earlier versions.
/// Without Firebase only the products added on this device.
Future<List<Part>> loadProductCatalog({CloudInventory? cloud}) async {
  if (cloud != null) {
    final shared = await cloud.products.get();
    final products = shared.docs.map((doc) => productPart(doc.data())).toList()
      ..sort((a, b) => a.sku.compareTo(b.sku));
    final known = {for (final p in products) p.sku.toUpperCase()};
    final custom = await cloud.catalog.get();
    return [
      ...products,
      for (final doc in custom.docs)
        if (Part.fromJson(doc.data()) case final p
            when !known.contains(p.sku.toUpperCase()))
          p,
    ];
  }
  final prefs = await SharedPreferences.getInstance();
  final custom = jsonDecode(prefs.getString(_customCatalogKey) ?? '[]') as List;
  return [for (final row in custom) Part.fromJson(row)];
}

class ProductPhoto extends StatelessWidget {
  const ProductPhoto({
    super.key,
    required this.part,
    this.size = 64,
    this.height,
  });
  final Part part;
  final double size;
  final double? height;

  /// The picture bundled with the app: shown without Firebase and for a
  /// picture the database does not have.
  Widget get _bundled => Image.asset(
    part.imageAsset,
    fit: BoxFit.contain,
    errorBuilder: (_, error, stack) => const Icon(Icons.broken_image_outlined),
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: height ?? size,
    child: part.imageAsset.isEmpty
        ? const Icon(Icons.inventory_2_outlined)
        : !ProductImages.enabled
        ? _bundled
        : FutureBuilder<Uint8List?>(
            // Keyed by the picture, so a row reused for another product
            // does not show the previous one while loading.
            key: ValueKey(ProductImages.nameOf(part.imageAsset)),
            future: ProductImages.load(part.imageAsset),
            builder: (context, picture) {
              if (picture.connectionState != ConnectionState.done) {
                return const SizedBox.shrink();
              }
              final bytes = picture.data;
              if (bytes == null) return _bundled;
              return Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, error, stack) => _bundled,
              );
            },
          ),
  );
}

class ProductCatalogPage extends StatefulWidget {
  const ProductCatalogPage({super.key});
  @override
  State<ProductCatalogPage> createState() => _ProductCatalogPageState();
}

class _ProductCatalogPageState extends State<ProductCatalogPage> {
  late Future<List<Part>> catalog;
  CloudInventory? cloud;

  /// The products marked to be ordered; shown and changed on every row.
  late OrderList orders;
  final catalogSubscriptions = <StreamSubscription<dynamic>>[];
  bool initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = CloudInventoryScope.of(context);
    if (!initialized || next != cloud) {
      if (initialized) orders.dispose();
      initialized = true;
      cloud = next;
      orders = OrderList(cloud);
      for (final s in catalogSubscriptions) {
        s.cancel();
      }
      catalogSubscriptions.clear();
      catalog = loadProductCatalog(cloud: cloud);
      for (final source in [?cloud?.products, ?cloud?.catalog]) {
        catalogSubscriptions.add(
          source
              .snapshots()
              .skip(1)
              .listen(
                (_) {
                  if (mounted) {
                    setState(() => catalog = loadProductCatalog(cloud: cloud));
                  }
                },
                onError: (Object error) {
                  if (mounted) {
                    setState(() => catalog = Future<List<Part>>.error(error));
                  }
                },
              ),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final s in catalogSubscriptions) {
      s.cancel();
    }
    orders.dispose();
    super.dispose();
  }

  String query = '';

  Future<void> openOrderList() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => OrderListPage(orders: orders, catalog: catalog),
    ),
  );

  Future<void> createProduct() async {
    final products = await catalog;
    if (!mounted) return;
    final created = await Navigator.of(context).push<Part>(
      MaterialPageRoute(
        builder: (_) => _NewProductPage(products: products, cloud: cloud),
      ),
    );
    if (created == null || !mounted) return;
    setState(() {
      catalog = loadProductCatalog(cloud: cloud);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Product catalog'),
      actions: [
        ListenableBuilder(
          listenable: orders,
          builder: (context, _) => IconButton(
            tooltip: 'Order list',
            onPressed: openOrderList,
            icon: Badge(
              isLabelVisible: orders.length > 0,
              label: Text('${orders.length}'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
        ),
      ],
    ),
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
              labelText: 'Search product or either number',
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
                    (p) =>
                        '${p.name} ${p.productIdentification} ${p.supplierOrderNumber} ${p.category}'
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
                  return InkWell(
                    onTap: () => Navigator.pop(context, p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ProductPhoto(
                            part: p,
                            size: double.infinity,
                            height: 320,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.productIdentification.isEmpty
                                          ? p.supplierOrderNumber
                                          : p.productIdentification,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      [
                                        p.name,
                                        // Without a product ID of ours the
                                        // order number is the title above.
                                        if (p
                                                .productIdentification
                                                .isNotEmpty &&
                                            p.supplierOrderNumber.isNotEmpty)
                                          'Order no.: ${p.supplierOrderNumber}',
                                      ].join('\n'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              OrderQuantityControl(orders: orders, sku: p.sku),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ],
                      ),
                    ),
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

/// The number a new product is kept under: our product ID, else the
/// supplier order number (as for the supplier's catalogue products), else
/// the name in upper case with dashes ("Loctite 243" → "LOCTITE-243"), for
/// supplies that have no number at all.
String newProductSku({
  required String productId,
  required String supplierNumber,
  required String name,
}) {
  if (productId.trim().isNotEmpty) return productId.trim();
  if (supplierNumber.trim().isNotEmpty) return supplierNumber.trim();
  return name
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

class _NewProductPage extends StatefulWidget {
  const _NewProductPage({required this.products, this.cloud});
  final CloudInventory? cloud;
  final List<Part> products;

  @override
  State<_NewProductPage> createState() => _NewProductPageState();
}

class _NewProductPageState extends State<_NewProductPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final productNumber = TextEditingController();
  final orderNumber = TextEditingController();
  String category = categories.first;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    productNumber.dispose();
    orderNumber.dispose();
    super.dispose();
  }

  String get sku => newProductSku(
    productId: productNumber.text,
    supplierNumber: orderNumber.text,
    name: name.text,
  );

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      if (widget.cloud != null) {
        final row = {
          'sku': sku.toUpperCase(),
          'name': name.text.trim(),
          'category': category,
          'supplierSku': orderNumber.text.trim(),
          'imageAsset': '',
          'priceCents': 0,
        };
        await widget.cloud!.saveProduct(row);
        if (mounted) Navigator.pop(context, productPart(row));
        return;
      }
      final product = Part(
        id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
        name: name.text.trim(),
        sku: sku,
        // Kept under its supplier number, a product has no ID of ours.
        productNumber: sku == orderNumber.text.trim() ? '' : sku,
        orderNumber: orderNumber.text.trim(),
        category: category,
      );
      final prefs = await SharedPreferences.getInstance();
      final custom =
          jsonDecode(prefs.getString(_customCatalogKey) ?? '[]') as List;
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
            controller: productNumber,
            decoration: const InputDecoration(
              labelText: 'Our product ID',
              helperText:
                  'Optional. Without one the supplier order number is used, '
                  'else the name.',
              helperMaxLines: 2,
            ),
            validator: (value) {
              final code = sku.toLowerCase();
              // Without a name there is nothing to check yet.
              if (code.isEmpty) return null;
              if (widget.products.any(
                (p) =>
                    p.productIdentification.toLowerCase() == code ||
                    p.sku.toLowerCase() == code,
              )) {
                return (value?.trim() ?? '').isNotEmpty
                    ? 'This product ID is already in the catalog'
                    : orderNumber.text.trim().isNotEmpty
                    ? 'This supplier order number is already in the catalog'
                    : 'A product with this name is already in the catalog';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: orderNumber,
            decoration: const InputDecoration(
              labelText: 'Supplier order number',
            ),
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
