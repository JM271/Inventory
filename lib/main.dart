import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'catalog_migration.dart';
import 'cloud_inventory.dart';
import 'stock_changes_page.dart';
import 'firebase_gate.dart';

import 'dart:convert';

import 'dart:typed_data';

import 'inventory_pdf.dart';
import 'pdf_report_page.dart';

import 'part.dart';
import 'product_catalog.dart';
import 'test_stock.dart';
import 'brand.dart';
import 'report_dialog.dart';
export 'part.dart';
export 'product_catalog.dart' show categories;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InventoryApp(useFirebase: true));
}

// Black and white like the Molenstraat logo; warnings use the error red.
const ink = Colors.black;
const paper = Color(0xFFF6F6F6);
const line = Color(0xFFE2E2E2);

class InventoryApp extends StatelessWidget {
  const InventoryApp({super.key, this.useFirebase = false});
  final bool useFirebase;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Spoke · Workshop inventory',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.black,
        dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
      ),
      scaffoldBackgroundColor: paper,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: line),
        ),
      ),
    ),
    home: useFirebase
        ? FirebaseGate(
            inventoryBuilder: (store, admin) =>
                InventoryPage(cloud: store, admin: admin),
          )
        : const InventoryPage(),
  );
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({
    super.key,
    this.openPdfReport,
    this.cloud,
    this.admin = false,
  });
  final CloudInventory? cloud;
  final bool admin;
  final Future<void> Function(Uint8List)? openPdfReport;
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  List<Part> parts = [];
  String query = '', category = 'All parts';
  StockSite? stockSite;
  int visibleQuantity(Part p) =>
      stockSite == null ? p.totalQuantity : p.quantityAt(stockSite!);
  bool visibleLow(Part p) => stockSite == null ? p.low : p.lowAt(stockSite!);

  /// With a site selected, only parts kept there: in stock at that site or
  /// with a minimum for it (so parts to restock there still show).
  bool atSite(Part p) =>
      stockSite == null ||
      p.quantityAt(stockSite!) > 0 ||
      p.minimumAt(stockSite!) > 0;
  bool lowOnly = false, loading = true, exportingReport = false;

  /// Compact list that shows only the product names; remembered per device.
  bool namesOnly = false;
  SharedPreferences? prefs;
  StreamSubscription<dynamic>? cloudSubscription, priceSubscription;

  /// Catalogue prices in cents by upper-case SKU (bexio, shared with the
  /// offers app). Parts carry no price themselves.
  Map<String, int> prices = {};
  void setPrices(Iterable<Map<String, dynamic>> rows) {
    final next = {
      for (final row in rows)
        if ((row['sku'] as String? ?? '').trim().toUpperCase() case final sku
            when sku.isNotEmpty)
          sku: (row['priceCents'] as num? ?? 0).toInt(),
    };
    if (mounted) setState(() => prices = next);
  }

  /// The part's catalogue price in cents, or null if it has none.
  int? priceOf(Part p) {
    final cents =
        prices[p.sku.trim().toUpperCase()] ??
        prices[p.productNumber.toUpperCase()];
    return cents == null || cents <= 0 ? null : cents;
  }

  bool cloudBusy = false, fromCache = true;

  @override
  void dispose() {
    cloudSubscription?.cancel();
    priceSubscription?.cancel();
    super.dispose();
  }

  Future<void> cloudWrite(Future<void> Function() action) async {
    if (cloudBusy) return;
    setState(() => cloudBusy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(cloudError(e))));
      }
    } finally {
      if (mounted) setState(() => cloudBusy = false);
    }
  }

  Future<void> importLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("workshop_parts");
    final local = (jsonDecode(raw ?? "[]") as List)
        .map((p) => Part.fromJson(p))
        .where((p) => !p.name.startsWith("[TEST]"))
        .toList();
    final custom = (jsonDecode(
      prefs.getString('custom_product_catalog_v1') ?? '[]',
    ) as List).map((p) => Part.fromJson(p)).toList();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Lokalen Bestand übernehmen?"),
        content: Text(
          "${local.length} Lagerartikel und ${custom.length} eigene Katalogprodukte in das bisher unbenutzte gemeinsame Lager übernehmen. Testartikel werden ausgelassen. Die lokalen Daten bleiben erhalten. Ein bereits verwendetes gemeinsames Lager wird nicht überschrieben.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Abbrechen"),
          ),
          FilledButton(
            onPressed: local.isEmpty && custom.isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: const Text("Übernehmen"),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await cloudWrite(() => widget.cloud!.importLocal(local, custom: custom));
    }
  }

  String? storageError;
  @override
  void initState() {
    super.initState();
    load();
    SharedPreferences.getInstance().then((p) {
      final v = p.getBool('names_only_view') ?? false;
      if (mounted && v != namesOnly) setState(() => namesOnly = v);
    }, onError: (_) {});
  }

  void setNamesOnly(bool v) {
    setState(() => namesOnly = v);
    SharedPreferences.getInstance().then(
      (p) => p.setBool('names_only_view', v),
      onError: (_) => false,
    );
  }

  Future<void> loadPrices() async {
    try {
      final bundled = await loadBundledProducts();
      setPrices(bundled);
      if (widget.cloud == null || !mounted) return;
      priceSubscription = widget.cloud!.products.snapshots().listen((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          setPrices(snapshot.docs.map((d) => d.data()));
        }
      }, onError: (Object e) => debugPrint('Preise nicht geladen: $e'));
    } catch (e) {
      debugPrint('Preise nicht geladen: $e');
    }
  }

  Future<void> load() async {
    loadPrices();
    if (widget.cloud != null) {
      // Fills the shared catalogue on first use; harmless afterwards.
      loadBundledProducts().then(widget.cloud!.seedProducts).catchError((
        Object e,
      ) {
        debugPrint('Katalog nicht eingerichtet: $e');
        return false;
      });
      cloudSubscription = widget.cloud!.parts
          .snapshots(includeMetadataChanges: true)
          .listen(
            (snapshot) {
              if (!mounted) return;
              setState(() {
                parts = snapshot.docs
                    .map((doc) => Part.fromJson(doc.data()))
                    .toList();
                fromCache = snapshot.metadata.isFromCache;
                storageError = null;
                loading = false;
              });
            },
            onError: (Object error) {
              if (!mounted) return;
              setState(() {
                parts = [];
                loading = false;
                storageError = cloudError(error);
              });
            },
          );
      return;
    }
    try {
      prefs = await SharedPreferences.getInstance();
      final raw = prefs!.getString('workshop_parts');
      if (raw != null) {
        parts = (jsonDecode(raw) as List).map((j) => Part.fromJson(j)).toList();
      }
      if (!(prefs!.getBool('test_stock_added_v1') ?? false)) {
        parts = addTestStock(parts, await loadProductCatalog());
        final saved = await prefs!.setString(
          'workshop_parts',
          jsonEncode(parts.map((p) => p.toJson()).toList()),
        );
        if (!saved || !await prefs!.setBool('test_stock_added_v1', true)) {
          throw StateError('Could not save test stock');
        }
      }
    } catch (_) {
      storageError = 'Could not load saved stock. Please restart the app before making changes.';
    }
    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> save() async {
    try {
      final previous = (jsonDecode(
        prefs!.getString('workshop_parts') ?? '[]',
      ) as List).map((j) => Part.fromJson(j)).toList();
      final history =
          (jsonDecode(prefs!.getString('stock_changes_v1') ?? '[]') as List);
      final before = {for (final p in previous) p.id: p};
      final after = {for (final p in parts) p.id: p};
      final additions = <Map<String, dynamic>>[];
      for (final id in {...before.keys, ...after.keys}) {
        final old = before[id], next = after[id];
        if (old != null &&
            next != null &&
            old.quantity == next.quantity &&
            old.carQuantity == next.carQuantity &&
            old.garageQuantity == next.garageQuantity) {
          continue;
        }
        final p = next ?? old!;
        additions.add({
          'partId': p.id,
          'name': p.name,
          'productNumber': p.productIdentification,
          'action': old == null
              ? 'Added'
              : next == null
              ? 'Deleted'
              : 'Changed',
          'beforeWorkshop': old?.quantity ?? 0,
          'afterWorkshop': next?.quantity ?? 0,
          'beforeCar': old?.carQuantity ?? 0,
          'afterCar': next?.carQuantity ?? 0,
          'beforeGarage': old?.garageQuantity ?? 0,
          'afterGarage': next?.garageQuantity ?? 0,
          'uid': 'This device',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
      }
      final saved = await prefs!.setString(
        'workshop_parts',
        jsonEncode(parts.map((p) => p.toJson()).toList()),
      );
      if (!saved) throw StateError('Save failed');
      if (!await prefs!.setString(
        'stock_changes_v1',
        jsonEncode([...additions.reversed, ...history].take(200).toList()),
      )) {
        throw StateError('History save failed');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 15),
            action: SnackBarAction(label: 'Retry save', onPressed: save),
            content: const Text(
              'Stock could not be saved. Keep the app open and try again.',
            ),
          ),
        );
      }
    }
  }

  IconData iconFor(String c) => switch (c) {
    'Drivetrain' => Icons.settings_outlined,
    'Brakes' => Icons.disc_full_outlined,
    'Wheels & tyres' => Icons.trip_origin,
    'Tools' => Icons.handyman_outlined,
    'Consumables' => Icons.water_drop_outlined,
    _ => Icons.pedal_bike_outlined,
  };

  /// The stock change log, or one part's history; entries open their part.
  Future<void> showHistory([Part? part]) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => StockChangesPage(
        cloud: widget.cloud,
        admin: widget.admin,
        partId: part?.id,
        partName: part?.name,
        onOpenPart: (id) {
          final match = parts.where((p) => p.id == id).firstOrNull;
          if (match != null) {
            edit(match);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Dieser Artikel wurde gelöscht.')),
            );
          }
        },
      ),
    ),
  );

  Future<void> edit([Part? part]) async {
    if (cloudBusy) return;
    final baseline = {for (final p in parts) p.id: Part.fromJson(p.toJson())};
    final result = await showModalBottomSheet<Part>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PartEditor(part: part, existingParts: parts),
    );
    if (result == null || !mounted) {
      return;
    }
    if (widget.cloud != null) {
      await cloudWrite(
        () => widget.cloud!.savePart(result, expected: baseline[result.id]),
      );
      return;
    }
    setState(() {
      final index = parts.indexWhere((p) => p.id == result.id);
      if (index < 0) {
        parts.add(result);
      } else {
        parts[index] = result;
      }
    });
    await save();
  }

  Future<PdfReportSnapshot> createPdfReport() async {
    final now = DateTime.now().toUtc();
    final snapshot = parts.map((p) => Part.fromJson(p.toJson())).toList();
    return PdfReportSnapshot(
      bytes: await buildInventoryPdf(snapshot, now),
      filename: 'Inventory-${now.toIso8601String().replaceAll(':', '-')}.pdf',
      generatedAt: now,
    );
  }

  Future<void> exportReport(BuildContext buttonContext) async {
    if (exportingReport) return;
    setState(() => exportingReport = true);
    try {
      final report = await createPdfReport();
      if (!mounted) return;
      if (widget.openPdfReport != null) {
        await widget.openPdfReport!(report.bytes);
      } else {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => PdfReportPage(
              initialReport: report,
              onRefresh: createPdfReport,
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Der PDF-Bericht konnte nicht erstellt werden. Dein Lagerbestand ist unverändert. Bitte erneut versuchen.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => exportingReport = false);
    }
  }

  Future<void> selectProduct() async {
    final selected = await Navigator.of(
      context,
    ).push<Part>(MaterialPageRoute(builder: (_) => const ProductCatalogPage()));
    if (selected == null || !mounted) return;
    final existing = parts.where(
      (p) => p.sku.toLowerCase() == selected.sku.toLowerCase(),
    );
    await edit(existing.isNotEmpty ? existing.first : selected);
  }

  Future<void> adjust(Part part, StockSite site, int delta) async {
    if (cloudBusy || part.quantityAt(site) + delta < 0) return;
    if (widget.cloud != null) {
      await cloudWrite(() => widget.cloud!.adjust(part.id, site, delta));
      return;
    }
    setState(() => part.adjustAt(site, delta));
    await save();
  }

  Future<void> transfer(Part part) async {
    if (cloudBusy) return;
    var amount = '1';
    final form = GlobalKey<FormState>();
    var from = stockSite ?? StockSite.workshop;
    var to = from == StockSite.workshop ? StockSite.car : StockSite.workshop;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Umlagern'),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(part.name),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<StockSite>(
                    isExpanded: true,
                    initialValue: from,
                    decoration: const InputDecoration(labelText: 'Von'),
                    items: [
                      for (final site in StockSite.values)
                        DropdownMenuItem(value: site, child: Text(site.label)),
                    ],
                    onChanged: (site) => update(() {
                      from = site!;
                      if (to == from) {
                        to = StockSite.values.firstWhere((s) => s != from);
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<StockSite>(
                    key: ValueKey(from),
                    isExpanded: true,
                    initialValue: to,
                    decoration: const InputDecoration(labelText: 'Nach'),
                    items: [
                      for (final site in StockSite.values)
                        if (site != from)
                          DropdownMenuItem(
                            value: site,
                            child: Text(site.label),
                          ),
                    ],
                    onChanged: (site) => update(() => to = site!),
                  ),
                  const SizedBox(height: 12),
                  Text('Verfügbar in ${from.label}: ${part.quantityAt(from)}'),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: amount,
                    onChanged: (value) => amount = value,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Menge'),
                    validator: (value) {
                      final number = int.tryParse(value ?? '');
                      return number == null ||
                              number <= 0 ||
                              number > part.quantityAt(from)
                          ? 'Menge zwischen 1 und ${part.quantityAt(from)} eingeben'
                          : null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(context, true);
              },
              child: const Text('Umlagern'),
            ),
          ],
        ),
      ),
    );
    final count = int.tryParse(amount);
    if (confirmed == true && mounted && count != null) {
      if (widget.cloud != null) {
        await cloudWrite(
          () => widget.cloud!.transfer(part.id, from, to, count),
        );
        return;
      }
      setState(() => part.transfer(from, to, count));
      await save();
    }
  }

  Widget stockRow(Part p, StockSite site) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 12, 4),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                site.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                p.lowAt(site)
                    ? 'Nachbestellen · min. ${p.minimumAt(site)}'
                    : 'Min. ${p.minimumAt(site)}',
                style: TextStyle(
                  fontSize: 12,
                  color: p.lowAt(site)
                      ? Theme.of(context).colorScheme.error
                      : ink,
                ),
              ),
            ],
          ),
        ),
        IconButton.outlined(
          tooltip: 'Use one · ${site.label}',
          onPressed: p.quantityAt(site) == 0 ? null : () => adjust(p, site, -1),
          icon: const Icon(Icons.remove, size: 18),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${p.quantityAt(site)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton.outlined(
          tooltip: 'Receive one · ${site.label}',
          onPressed: () => adjust(p, site, 1),
          icon: const Icon(Icons.add, size: 18),
        ),
      ],
    ),
  );

  Future<void> remove(Part part) async {
    if (cloudBusy) return;
    final expected = Part.fromJson(part.toJson());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete part?'),
        content: Text('Remove ${part.name} from your inventory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      if (widget.cloud != null) {
        await cloudWrite(() => widget.cloud!.deletePart(expected));
        return;
      }
      setState(() => parts.remove(part));
      await save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered =
        parts
            .where(
              (p) =>
                  atSite(p) &&
                  (!lowOnly || visibleLow(p)) &&
                  (category == 'All parts' || p.category == category) &&
                  '${p.name} ${p.productIdentification} ${p.supplierOrderNumber} ${p.location}'
                      .toLowerCase()
                      .contains(query.toLowerCase()),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return Scaffold(
      appBar: AppBar(
        title: const Align(alignment: Alignment.centerLeft, child: BrandLogo()),
        actions: [
          if (widget.cloud != null)
            PopupMenuButton<String>(
              tooltip: 'Konto und Synchronisierung',
              enabled: !cloudBusy,
              icon: const Icon(Icons.account_circle_outlined),
              onSelected: (value) async {
                if (value == 'users') {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => UsersPage(store: widget.cloud!),
                    ),
                  );
                } else if (value == 'catalog') {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => CatalogMigrationPage(
                        cloud: widget.cloud!,
                        parts: parts,
                      ),
                    ),
                  );
                } else if (value == 'import') {
                  try {
                    await importLocal();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(cloudError(e))));
                    }
                  }
                } else {
                  await FirebaseAuth.instance.signOut();
                }
              },
              itemBuilder: (_) => [
                if (widget.admin)
                  const PopupMenuItem(
                    value: 'users',
                    child: Text('Nutzer verwalten'),
                  ),
                if (widget.admin)
                  const PopupMenuItem(
                    value: 'catalog',
                    child: Text('Lager auf Katalog umstellen'),
                  ),
                if (widget.admin)
                  const PopupMenuItem(
                    value: 'import',
                    child: Text('Lokalen Bestand übernehmen'),
                  ),
                const PopupMenuItem(value: 'logout', child: Text('Abmelden')),
              ],
            ),
          IconButton(
            tooltip: 'Product catalog',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: loading || storageError != null ? null : selectProduct,
          ),
          IconButton(
            tooltip: 'Excel report to OneDrive',
            icon: const Icon(Icons.cloud_upload_outlined),
            onPressed: loading || storageError != null
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (_) => ReportDialog(
                      parts: parts
                          .map((p) => Part.fromJson(p.toJson()))
                          .toList(),
                    ),
                  ),
          ),
          Builder(
            builder: (buttonContext) => TextButton.icon(
              onPressed: loading || storageError != null || exportingReport
                  ? null
                  : () => exportReport(buttonContext),
              icon: exportingReport
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: const Text('Report'),
            ),
          ),
        ],
      ),
      floatingActionButton: loading || storageError != null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => edit(),
              backgroundColor: ink,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add part'),
            ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : storageError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(storageError!),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.history),
                        label: const Text('Letzte Bestandsänderungen'),
                        onPressed: () => showHistory(),
                      ),
                    ),
                    if (widget.cloud != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          children: [
                            Icon(
                              cloudBusy
                                  ? Icons.sync
                                  : fromCache
                                  ? Icons.cloud_off_outlined
                                  : Icons.cloud_done_outlined,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                cloudBusy
                                    ? 'Änderung wird gespeichert…'
                                    : fromCache
                                    ? 'Verbindung wird hergestellt · Buchungen benötigen Internet'
                                    : 'Gemeinsames Lager · Molenstraat',
                              ),
                            ),
                          ],
                        ),
                      ),
                    SegmentedButton<StockSite?>(
                      segments: const [
                        ButtonSegment(value: null, label: Text('Alle')),
                        ButtonSegment(
                          value: StockSite.workshop,
                          label: Text('Poya'),
                        ),
                        ButtonSegment(
                          value: StockSite.car,
                          label: Text('Auto'),
                        ),
                        ButtonSegment(
                          value: StockSite.garage,
                          label: Text('Garage'),
                        ),
                      ],
                      selected: {stockSite},
                      onSelectionChanged: (sites) =>
                          setState(() => stockSite = sites.single),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (v) => setState(() => query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search parts, either number or location',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['All parts', ...categories]
                            .map(
                              (c) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(c),
                                  selected: category == c,
                                  onSelected: (_) =>
                                      setState(() => category = c),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Inventory · ${filtered.length}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                              color: ink,
                            ),
                          ),
                        ),
                        FilterChip(
                          label: Text(
                            'Low stock · ${parts.where(visibleLow).length}',
                          ),
                          selected: lowOnly,
                          onSelected: (v) => setState(() => lowOnly = v),
                        ),
                        IconButton(
                          tooltip: namesOnly
                              ? 'Show details'
                              : 'Show names only',
                          icon: Icon(
                            namesOnly
                                ? Icons.view_agenda_outlined
                                : Icons.view_list,
                          ),
                          onPressed: () => setNamesOnly(!namesOnly),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (filtered.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 45,
                          horizontal: 24,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              size: 44,
                              color: ink,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              parts.isEmpty
                                  ? 'A tidy workshop starts here'
                                  : 'No matching parts',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              parts.isEmpty
                                  ? 'Add your first part and give it a place on the shelf.'
                                  : 'Try another search or change your filters.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.black54),
                            ),
                            if (parts.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 18),
                                child: FilledButton.icon(
                                  onPressed: () => edit(),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add your first part'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (namesOnly && filtered.isNotEmpty)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: line),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Material(
                          color: Colors.transparent,
                          child: Column(
                            children: [
                              for (final (i, p) in filtered.indexed) ...[
                                if (i > 0)
                                  const Divider(height: 1, color: line),
                                ListTile(
                                  dense: true,
                                  title: Text(
                                    p.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  // Stock at the selected site, or the
                                  // total over all sites; red when low.
                                  trailing: Text(
                                    '${visibleQuantity(p)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      color: visibleLow(p)
                                          ? Theme.of(context).colorScheme.error
                                          : ink,
                                    ),
                                  ),
                                  onTap: () => edit(p),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    if (!namesOnly)
                      ...filtered.map(
                        (p) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: line),
                          ),
                          child: Column(
                            children: [
                              if (p.imageAsset.isNotEmpty)
                                GestureDetector(
                                  onTap: () => edit(p),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      16,
                                      16,
                                      0,
                                    ),
                                    child: ProductPhoto(
                                      part: p,
                                      size: double.infinity,
                                      height: 320,
                                    ),
                                  ),
                                ),
                              Material(
                                color: Colors.transparent,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    4,
                                    0,
                                  ),
                                  leading: p.imageAsset.isNotEmpty
                                      ? null
                                      : CircleAvatar(
                                          backgroundColor: paper,
                                          foregroundColor: ink,
                                          child: Icon(iconFor(p.category)),
                                        ),
                                  title: Text(
                                    p.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      p.category,
                                      if (priceOf(p) case final cents?)
                                        formatChf(cents),
                                      if (p.productIdentification.isNotEmpty)
                                        'Product ID: ${p.productIdentification}',
                                      if (p.supplierOrderNumber.isNotEmpty)
                                        'Order no.: ${p.supplierOrderNumber}',
                                      if (p.location.isNotEmpty) p.location,
                                    ].join(' · '),
                                  ),
                                  onTap: () => edit(p),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (v) => switch (v) {
                                      'edit' => edit(p),
                                      'history' => showHistory(p),
                                      _ => remove(p),
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit part'),
                                      ),
                                      PopupMenuItem(
                                        value: 'history',
                                        child: Text('Verlauf'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete part'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              for (final site in StockSite.values)
                                if (stockSite == null || stockSite == site)
                                  stockRow(p, site),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  12,
                                  8,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Gesamt: ${p.totalQuantity}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: p.totalQuantity == 0
                                          ? null
                                          : () => transfer(p),
                                      icon: const Icon(Icons.swap_horiz),
                                      label: const Text('Umlagern'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class PartEditor extends StatefulWidget {
  const PartEditor({super.key, this.part, this.existingParts = const []});
  final Part? part;
  final List<Part> existingParts;
  @override
  State<PartEditor> createState() => _PartEditorState();
}

class _PartEditorState extends State<PartEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name,
      productNumber,
      orderNumber,
      location,
      quantity,
      minimum,
      carQuantity,
      carMinimum,
      garageQuantity,
      garageMinimum;
  late String category;
  Part? catalogPart;
  bool editingExisting = false;
  @override
  void initState() {
    super.initState();
    final p = widget.part;
    name = TextEditingController(text: p?.name);
    productNumber = TextEditingController(text: p?.productIdentification);
    orderNumber = TextEditingController(text: p?.supplierOrderNumber);
    location = TextEditingController(text: p?.location);
    quantity = TextEditingController(text: '${p?.quantity ?? 0}');
    minimum = TextEditingController(text: '${p?.minimum ?? 2}');
    carQuantity = TextEditingController(text: '${p?.carQuantity ?? 0}');
    carMinimum = TextEditingController(text: '${p?.carMinimum ?? 0}');
    garageQuantity = TextEditingController(text: '${p?.garageQuantity ?? 0}');
    garageMinimum = TextEditingController(text: '${p?.garageMinimum ?? 0}');
    category = p?.category ?? categories.first;
  }

  Future<void> chooseFromCatalog() async {
    FocusScope.of(context).unfocus();
    final selected = await Navigator.of(
      context,
    ).push<Part>(MaterialPageRoute(builder: (_) => const ProductCatalogPage()));
    if (selected == null || !mounted) return;
    final matches = widget.existingParts.where(
      (p) => p.sku.toLowerCase() == selected.sku.toLowerCase(),
    );
    final existing = widget.part == null ? matches.firstOrNull : null;
    setState(() {
      catalogPart = existing == null
          ? selected
          : (Part.fromJson(existing.toJson())
              ..imageAsset = selected.imageAsset);
      editingExisting = existing != null;
      name.text = catalogPart!.name;
      productNumber.text = catalogPart!.productIdentification;
      orderNumber.text = catalogPart!.supplierOrderNumber;
      category = catalogPart!.category;
      if (existing != null) {
        quantity.text = '${existing.quantity}';
        minimum.text = '${existing.minimum}';
        carQuantity.text = '${existing.carQuantity}';
        carMinimum.text = '${existing.carMinimum}';
        garageQuantity.text = '${existing.garageQuantity}';
        garageMinimum.text = '${existing.garageMinimum}';
        location.text = existing.location;
      }
    });
  }

  @override
  void dispose() {
    for (final c in [
      name,
      productNumber,
      orderNumber,
      location,
      quantity,
      minimum,
      carQuantity,
      carMinimum,
      garageQuantity,
      garageMinimum,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(
    String label,
    TextEditingController controller, {
    bool number = false,
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: number ? TextInputType.number : TextInputType.text,
      validator: (v) {
        if (required && (v == null || v.trim().isEmpty)) {
          return 'Enter a part name';
        }
        if (number && (int.tryParse(v ?? '') == null || int.parse(v!) < 0)) {
          return 'Enter a whole number, 0 or more';
        }
        return null;
      },
    ),
  );
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      24,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: Form(
      key: form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.part == null ? 'Add a part' : 'Edit part',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: chooseFromCatalog,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Aus Katalog wählen'),
            ),
            if (editingExisting)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Artikel bereits im Lager: Du bearbeitest den vorhandenen Bestand.',
                ),
              ),
            const SizedBox(height: 16),
            if ((catalogPart ?? widget.part)?.imageAsset.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Center(
                  child: ProductPhoto(
                    part: (catalogPart ?? widget.part)!,
                    size: 180,
                  ),
                ),
              ),
            field('Part name', name, required: true),
            DropdownButtonFormField<String>(
              key: ValueKey(category),
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: {
                ...categories,
                category,
              }.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => category = v!,
            ),
            const SizedBox(height: 16),
            field('Our product ID', productNumber),
            field('Supplier order number', orderNumber),
            field('Location (e.g. Shelf A · Bin 3)', location),
            const Text('Poya', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: field('Quantity', quantity, number: true)),
                const SizedBox(width: 12),
                Expanded(child: field('Minimum stock', minimum, number: true)),
              ],
            ),
            const Text('Auto', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: field('Menge Auto', carQuantity, number: true)),
                const SizedBox(width: 12),
                Expanded(
                  child: field('Minimum Auto', carMinimum, number: true),
                ),
              ],
            ),
            const Text('Garage', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: field('Menge Garage', garageQuantity, number: true),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: field('Minimum Garage', garageMinimum, number: true),
                ),
              ],
            ),
            const Text(
              'Mindestbestand je Lager. Minimum 0 bei Auto oder Garage deaktiviert dort die Nachbestellwarnung.',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(
                    context,
                    Part(
                      id:
                          widget.part?.id ??
                          catalogPart?.id ??
                          DateTime.now().microsecondsSinceEpoch.toString(),
                      name: name.text.trim(),
                      category: category,
                      sku:
                          catalogPart?.sku ??
                          widget.part?.sku ??
                          productNumber.text.trim(),
                      productNumber: productNumber.text.trim(),
                      orderNumber: orderNumber.text.trim(),
                      imageAsset:
                          (catalogPart ?? widget.part)?.imageAsset ?? '',
                      location: location.text.trim(),
                      quantity: int.parse(quantity.text),
                      minimum: int.parse(minimum.text),
                      carQuantity: int.parse(carQuantity.text),
                      carMinimum: int.parse(carMinimum.text),
                      garageQuantity: int.parse(garageQuantity.text),
                      garageMinimum: int.parse(garageMinimum.text),
                    ),
                  );
                }
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Save part'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Swiss franc amount from cents, e.g. 269000 → "CHF 2'690.00".
String formatChf(int cents) {
  final francs = (cents ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+$)'),
    (_) => "'",
  );
  return 'CHF $francs.${(cents % 100).toString().padLeft(2, '0')}';
}
