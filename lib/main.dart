import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'cloud_inventory.dart';
import 'firebase_gate.dart';

import 'dart:convert';

import 'dart:typed_data';

import 'inventory_pdf.dart';
import 'pdf_report_page.dart';

import 'part.dart';
import 'product_catalog.dart';
import 'test_stock.dart';
import 'report_dialog.dart';
export 'part.dart';
export 'product_catalog.dart' show categories;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InventoryApp(useFirebase: true));
}

const ink = Color(0xFF172C29);
const green = Color(0xFF286653);

class InventoryApp extends StatelessWidget {
  const InventoryApp({super.key, this.useFirebase = false});
  final bool useFirebase;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Spoke · Workshop inventory',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: green),
      scaffoldBackgroundColor: const Color(0xFFF5F6F2),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF5F6F2),
        foregroundColor: ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDEE4DD)),
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
  bool lowOnly = false, loading = true, exportingReport = false;
  SharedPreferences? prefs;
  StreamSubscription<dynamic>? cloudSubscription;
  bool cloudBusy = false, fromCache = true;

  @override
  void dispose() {
    cloudSubscription?.cancel();
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
  }

  Future<void> load() async {
    if (widget.cloud != null) {
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
      final saved = await prefs!.setString(
        'workshop_parts',
        jsonEncode(parts.map((p) => p.toJson()).toList()),
      );
      if (!saved) {
        throw StateError('Save failed');
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
                    decoration: const InputDecoration(labelText: 'Richtung'),
                    items: StockSite.values
                        .map(
                          (site) => DropdownMenuItem(
                            value: site,
                            child: Text(
                              site == StockSite.workshop
                                  ? 'Werkstatt → Auto'
                                  : 'Auto → Werkstatt',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (site) => update(() => from = site!),
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
        await cloudWrite(() => widget.cloud!.transfer(part.id, from, count));
        return;
      }
      setState(() => part.transfer(from, count));
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
                  color: p.lowAt(site) ? const Color(0xFFA55C1B) : green,
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
                  (!lowOnly || visibleLow(p)) &&
                  (category == 'All parts' || p.category == category) &&
                  '${p.name} ${p.sku} ${p.location}'.toLowerCase().contains(
                    query.toLowerCase(),
                  ),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'spoke',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -1),
        ),
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
              backgroundColor: green,
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
                    const Text(
                      'Ready for the next repair.',
                      style: TextStyle(
                        fontSize: 28,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your parts, tools and workshop supplies in one place.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: ink,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: metric('${parts.length}', 'Part types'),
                          ),
                          Expanded(
                            child: metric(
                              '${parts.fold<int>(0, (sum, p) => sum + visibleQuantity(p))}',
                              'Units in stock',
                            ),
                          ),
                          Expanded(
                            child: metric(
                              '${parts.where(visibleLow).length}',
                              'Need restocking',
                              accent: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<StockSite?>(
                      segments: const [
                        ButtonSegment(value: null, label: Text('Alle')),
                        ButtonSegment(
                          value: StockSite.workshop,
                          label: Text('Werkstatt'),
                        ),
                        ButtonSegment(
                          value: StockSite.car,
                          label: Text('Auto'),
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
                        hintText: 'Search parts, SKU or location',
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
                          label: const Text('Low stock'),
                          selected: lowOnly,
                          onSelected: (v) => setState(() => lowOnly = v),
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
                              color: green,
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
                    ...filtered.map(
                      (p) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE4E8E1)),
                        ),
                        child: Column(
                          children: [
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
                                    ? ProductPhoto(part: p)
                                    : CircleAvatar(
                                        backgroundColor: const Color(
                                          0xFFEAF0E9,
                                        ),
                                        foregroundColor: green,
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
                                    if (p.sku.isNotEmpty) p.sku,
                                    if (p.location.isNotEmpty) p.location,
                                  ].join(' · '),
                                ),
                                onTap: () => edit(p),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (v) =>
                                      v == 'edit' ? edit(p) : remove(p),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit part'),
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
                              padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
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

  Widget metric(String value, String label, {bool accent = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: TextStyle(
          color: accent ? const Color(0xFFECC58B) : Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        label,
        style: const TextStyle(color: Color(0xFFCBD7CF), fontSize: 11),
      ),
    ],
  );
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
      sku,
      location,
      quantity,
      minimum,
      carQuantity,
      carMinimum;
  late String category;
  Part? catalogPart;
  bool editingExisting = false;
  @override
  void initState() {
    super.initState();
    final p = widget.part;
    name = TextEditingController(text: p?.name);
    sku = TextEditingController(text: p?.sku);
    location = TextEditingController(text: p?.location);
    quantity = TextEditingController(text: '${p?.quantity ?? 0}');
    minimum = TextEditingController(text: '${p?.minimum ?? 2}');
    carQuantity = TextEditingController(text: '${p?.carQuantity ?? 0}');
    carMinimum = TextEditingController(text: '${p?.carMinimum ?? 0}');
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
      sku.text = catalogPart!.sku;
      category = catalogPart!.category;
      if (existing != null) {
        quantity.text = '${existing.quantity}';
        minimum.text = '${existing.minimum}';
        carQuantity.text = '${existing.carQuantity}';
        carMinimum.text = '${existing.carMinimum}';
        location.text = existing.location;
      }
    });
  }

  @override
  void dispose() {
    for (final c in [
      name,
      sku,
      location,
      quantity,
      minimum,
      carQuantity,
      carMinimum,
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
              items: categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => category = v!,
            ),
            const SizedBox(height: 16),
            field('SKU / part number', sku),
            field('Location (e.g. Shelf A · Bin 3)', location),
            const Text(
              'Werkstatt',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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
            const Text(
              'Mindestbestand je Lager. Minimum Auto = 0 deaktiviert die Nachbestellwarnung im Auto.',
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
                      sku: sku.text.trim(),
                      imageAsset:
                          (catalogPart ?? widget.part)?.imageAsset ?? '',
                      location: location.text.trim(),
                      quantity: int.parse(quantity.text),
                      minimum: int.parse(minimum.text),
                      carQuantity: int.parse(carQuantity.text),
                      carMinimum: int.parse(carMinimum.text),
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
