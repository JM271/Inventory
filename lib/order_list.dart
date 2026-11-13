import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_inventory.dart';
import 'firebase_gate.dart' show cloudError;
import 'inventory_pdf.dart';
import 'part.dart';
import 'pdf_report_page.dart';
import 'product_catalog.dart';

const _localOrderListKey = 'order_list_v1';

/// One product on the order list with the quantity to order.
typedef OrderLine = ({Part product, int quantity});

/// The order list: catalogue products marked to be ordered, each with a
/// quantity. Shared through the database, so everyone adds to the same
/// list; without Firebase it is kept on this device.
class OrderList extends ChangeNotifier {
  OrderList(this.cloud) {
    final cloud = this.cloud;
    if (cloud == null) {
      _loadLocal();
      return;
    }
    _subscription = cloud.orderList.snapshots().listen(
      (snapshot) {
        _quantities = {
          for (final doc in snapshot.docs)
            if (_key(doc.data()['sku'] as String? ?? '') case final sku
                when sku.isNotEmpty)
              sku: (doc.data()['quantity'] as num? ?? 0).toInt(),
        }..removeWhere((_, quantity) => quantity <= 0);
        error = null;
        loaded = true;
        notifyListeners();
      },
      onError: (Object e) {
        error = e;
        loaded = true;
        notifyListeners();
      },
    );
  }

  final CloudInventory? cloud;
  StreamSubscription<dynamic>? _subscription;
  Map<String, int> _quantities = {};
  bool _disposed = false;

  /// False until the list was read for the first time.
  bool loaded = false;

  /// Set if the shared list cannot be read.
  Object? error;

  static String _key(String sku) => sku.trim().toUpperCase();

  /// Quantities by upper-case SKU.
  Map<String, int> get quantities => Map.unmodifiable(_quantities);
  int get length => _quantities.length;
  int quantityOf(String sku) => _quantities[_key(sku)] ?? 0;

  /// Puts [quantity] of the product on the list; 0 takes it off.
  Future<void> setQuantity(String sku, int quantity) async {
    final key = _key(sku);
    if (key.isEmpty) return;
    if (cloud != null) {
      // The snapshot listener shows the change at once.
      await cloud!.setOrderQuantity(key, quantity);
      return;
    }
    final next = {..._quantities};
    if (quantity <= 0) {
      next.remove(key);
    } else {
      next[key] = quantity;
    }
    await _saveLocal(next);
  }

  Future<void> clear() async {
    if (cloud != null) {
      await cloud!.clearOrderList();
      return;
    }
    await _saveLocal({});
  }

  /// The list joined with the catalogue, sorted by the number to order by.
  /// A product that left the catalogue stays on the list under its SKU.
  List<OrderLine> lines(List<Part> products) {
    final bySku = {for (final p in products) _key(p.sku): p};
    return [
      for (final MapEntry(key: sku, value: quantity) in _quantities.entries)
        (
          product:
              bySku[sku] ??
              Part(
                id: 'catalog-$sku',
                name: sku,
                category: '',
                sku: sku,
                productNumber: '',
                orderNumber: sku,
              ),
          quantity: quantity,
        ),
    ]..sort((a, b) {
      final byNumber = orderNumberOf(a.product)
          .toUpperCase()
          .compareTo(orderNumberOf(b.product).toUpperCase());
      return byNumber != 0
          ? byNumber
          : a.product.name.toLowerCase().compareTo(
              b.product.name.toLowerCase(),
            );
    });
  }

  Future<void> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved =
          jsonDecode(prefs.getString(_localOrderListKey) ?? '{}') as Map;
      _quantities = {
        for (final MapEntry(:key, :value) in saved.entries)
          if (value is int && value > 0) _key('$key'): value,
      };
    } catch (e) {
      error = e;
    }
    loaded = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> _saveLocal(Map<String, int> next) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_localOrderListKey, jsonEncode(next))) {
      throw StateError('Could not save the order list');
    }
    _quantities = next;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}

/// The number a product is ordered by: the supplier's, else our own.
String orderNumberOf(Part product) => product.supplierOrderNumber.isNotEmpty
    ? product.supplierOrderNumber
    : product.productIdentification;

/// The order list as text, one product per line with tabs between number,
/// quantity and name, so it pastes into a mail or into Excel columns.
String orderListText(List<OrderLine> lines) => [
  for (final (:product, :quantity) in lines)
    '${orderNumberOf(product)}\t$quantity\t${product.name}',
].join('\n');

/// Marks a product for the order list: an Order button, and once it is on
/// the list its quantity with − and +. Tapping the quantity lets you type it.
class OrderQuantityControl extends StatelessWidget {
  const OrderQuantityControl({
    super.key,
    required this.orders,
    required this.sku,
  });

  final OrderList orders;
  final String sku;

  Future<void> _set(BuildContext context, int quantity) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await orders.setQuantity(sku, quantity);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(cloudError(e))));
    }
  }

  Future<void> _type(BuildContext context, int current) async {
    final quantity = await showDialog<int>(
      context: context,
      builder: (_) => _QuantityDialog(initial: current),
    );
    if (quantity != null && context.mounted) await _set(context, quantity);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: orders,
    builder: (context, _) {
      final quantity = orders.quantityOf(sku);
      if (quantity == 0) {
        return OutlinedButton.icon(
          onPressed: orders.loaded ? () => _set(context, 1) : null,
          icon: const Icon(Icons.add_shopping_cart, size: 18),
          label: const Text('Order'),
        );
      }
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(24),
        ),
        child: IconTheme(
          data: const IconThemeData(color: Colors.white, size: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: quantity == 1
                    ? 'Remove from order list'
                    : 'Order less',
                visualDensity: VisualDensity.compact,
                icon: Icon(quantity == 1 ? Icons.delete_outline : Icons.remove),
                onPressed: () => _set(context, quantity - 1),
              ),
              InkWell(
                onTap: () => _type(context, quantity),
                child: Tooltip(
                  message: 'Enter quantity',
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 28),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '$quantity',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Order more',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add),
                onPressed: () => _set(context, quantity + 1),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({required this.initial});
  final int initial;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final controller = TextEditingController(text: '${widget.initial}');
  final form = GlobalKey<FormState>();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    if (form.currentState!.validate()) {
      Navigator.pop(context, int.parse(controller.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Quantity to order'),
    content: Form(
      key: form,
      child: TextFormField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(helperText: '0 removes the product'),
        validator: (value) {
          final quantity = int.tryParse(value?.trim() ?? '');
          return quantity == null || quantity > 100000
              ? 'Enter a number up to 100000'
              : null;
        },
        onFieldSubmitted: (_) => submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: submit, child: const Text('OK')),
    ],
  );
}

/// The products marked in the catalogue, with their quantities: change or
/// remove them, copy the list as text, open it as a PDF or empty it.
class OrderListPage extends StatefulWidget {
  const OrderListPage({
    super.key,
    required this.orders,
    required this.catalog,
    this.openPdf,
  });

  final OrderList orders;
  final Future<List<Part>> catalog;

  /// Replaces the PDF preview in tests.
  final Future<void> Function(Uint8List bytes)? openPdf;

  @override
  State<OrderListPage> createState() => _OrderListPageState();
}

class _OrderListPageState extends State<OrderListPage> {
  void show(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> copy(List<OrderLine> lines) async {
    await Clipboard.setData(ClipboardData(text: orderListText(lines)));
    if (mounted) show('Order list copied (${lines.length} products)');
  }

  Future<PdfReportSnapshot> createPdf() async {
    final now = DateTime.now().toUtc();
    final lines = widget.orders.lines(await widget.catalog);
    return PdfReportSnapshot(
      bytes: await buildOrderListPdf(lines, now),
      filename: 'Order-list-${now.toIso8601String().substring(0, 10)}.pdf',
      generatedAt: now,
    );
  }

  Future<void> openPdf() async {
    try {
      final pdf = await createPdf();
      if (!mounted) return;
      if (widget.openPdf != null) {
        await widget.openPdf!(pdf.bytes);
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PdfReportPage(
            title: 'Order list · PDF',
            initialReport: pdf,
            onRefresh: createPdf,
          ),
        ),
      );
    } catch (_) {
      if (mounted) show('Could not create the PDF. Please try again.');
    }
  }

  Future<void> clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty the order list?'),
        content: Text(
          'All ${widget.orders.length} products are taken off the list'
          '${widget.orders.cloud != null ? ', for everyone' : ''}. '
          'Stock is not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Empty list'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.orders.clear();
    } catch (e) {
      if (mounted) show(cloudError(e));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Part>>(
    future: widget.catalog,
    builder: (context, snapshot) => ListenableBuilder(
      listenable: widget.orders,
      builder: (context, _) {
        final orders = widget.orders;
        final ready = snapshot.hasData && orders.loaded && orders.error == null;
        final lines = ready
            ? orders.lines(snapshot.data!)
            : const <OrderLine>[];
        final pieces = lines.fold<int>(0, (sum, l) => sum + l.quantity);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Order list'),
            actions: [
              IconButton(
                tooltip: 'Copy as text',
                icon: const Icon(Icons.copy_outlined),
                onPressed: lines.isEmpty ? null : () => copy(lines),
              ),
              IconButton(
                tooltip: 'Open as PDF',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: lines.isEmpty ? null : openPdf,
              ),
              IconButton(
                tooltip: 'Empty the order list',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: lines.isEmpty ? null : clear,
              ),
            ],
          ),
          body: snapshot.hasError || orders.error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      orders.error != null
                          ? 'Could not load the order list. ${cloudError(orders.error!)}'
                          : 'Could not load the product catalog. Close and reopen it to retry.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : !ready
              ? const Center(child: CircularProgressIndicator())
              : lines.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nothing to order yet. Go back to the catalog and tap '
                      'Order on every product you need.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: lines.length + 1,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Text(
                          '${lines.length} products · $pieces pieces',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      );
                    }
                    final (:product, :quantity) = lines[index - 1];
                    final number = orderNumberOf(product);
                    final ours = product.productIdentification;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          ProductPhoto(part: product, size: 56),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  number,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(product.name),
                                if (ours.isNotEmpty && ours != number)
                                  Text(
                                    'Our ID: $ours',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          OrderQuantityControl(
                            orders: orders,
                            sku: product.sku,
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    ),
  );
}
