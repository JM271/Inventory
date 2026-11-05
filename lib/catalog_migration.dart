import 'package:flutter/material.dart';

import 'cloud_inventory.dart';
import 'part.dart';
import 'product_catalog.dart';

/// One stock part and the catalogue product it is switched to.
class MigrationRow {
  MigrationRow(this.part, this.target, this.reason);

  final Part part;

  /// Catalogue product the part becomes; null keeps the part as it is.
  Part? target;

  /// Why [target] was suggested, shown in the preview.
  final String reason;
}

/// One write of the switch: [after] replaces [before]; a null [after]
/// deletes the part because its stock was added to another one.
typedef PartChange = ({Part before, Part? after});

/// Suggests a catalogue product for every stock part that is not yet
/// exactly a catalogue product: by our product ID first, then by a supplier
/// number that belongs to exactly one product. Parts without a match are
/// kept unless a product is chosen for them.
List<MigrationRow> planCatalogMigration(List<Part> parts, List<Part> products) {
  final bySku = {for (final p in products) _key(p.sku): p};
  final bySupplier = <String, List<Part>>{};
  for (final p in products) {
    final supplier = _key(p.orderNumber);
    if (supplier.isNotEmpty) (bySupplier[supplier] ??= []).add(p);
  }
  final rows = <MigrationRow>[];
  for (final part in parts) {
    final current = bySku[_key(part.sku)];
    if (current != null) {
      if (!_isUpToDate(part, current)) {
        rows.add(MigrationRow(part, current, 'Angaben aus dem Katalog'));
      }
      continue;
    }
    var target = bySku[_key(part.productNumber)];
    var reason = 'Eigene Produktnummer ${part.productNumber}';
    if (target == null) {
      for (final number in {_key(part.sku), _key(part.orderNumber)}) {
        final candidates = bySupplier[number];
        if (candidates != null && candidates.length == 1) {
          target = candidates.single;
          reason = 'Lieferantennummer ${part.sku}';
          break;
        }
      }
    }
    rows.add(
      MigrationRow(
        part,
        target,
        target == null ? 'Kein Katalogprodukt' : reason,
      ),
    );
  }
  rows.sort((a, b) {
    if ((a.target == null) != (b.target == null)) {
      return a.target == null ? 1 : -1;
    }
    return a.part.name.toLowerCase().compareTo(b.part.name.toLowerCase());
  });
  return rows;
}

/// The writes for [rows]: every part with a target gets the product's
/// number, name, category and picture. Several parts with the same target
/// are merged into one: quantities are added, the highest minimum and the
/// first location are kept, the other parts are deleted. Stock is never
/// lost: the total per site stays the same.
List<PartChange> buildCatalogMigration(
  List<MigrationRow> rows,
  List<Part> parts,
) {
  final groups = <String, List<Part>>{};
  final targets = <String, Part>{};
  for (final row in rows) {
    final target = row.target;
    if (target == null) continue;
    final key = _key(target.sku);
    targets[key] = target;
    (groups[key] ??= []).add(row.part);
  }
  final changes = <PartChange>[];
  for (final MapEntry(:key, value: members) in groups.entries) {
    final target = targets[key]!;
    // A part already on this product (not in the preview) takes the stock.
    final group = [
      ...parts.where(
        (p) => _key(p.sku) == key && !members.any((m) => m.id == p.id),
      ),
      ...members,
    ];
    final keeper = group.firstWhere(
      (p) => _key(p.sku) == key,
      orElse: () => group.first,
    );
    final old = keeper;
    final supplier = target.orderNumber.isNotEmpty
        ? target.orderNumber
        : old.orderNumber.isNotEmpty
        ? old.orderNumber
        : (_key(old.sku) != key ? old.sku : '');
    final after = Part.fromJson(keeper.toJson())
      ..sku = target.sku
      ..productNumber = target.sku
      ..orderNumber = supplier
      ..name = target.name
      ..category = target.category
      ..imageAsset = target.imageAsset.isNotEmpty
          ? target.imageAsset
          : keeper.imageAsset
      ..quantity = group.fold(0, (sum, p) => sum + p.quantity)
      ..carQuantity = group.fold(0, (sum, p) => sum + p.carQuantity)
      ..minimum = group.map((p) => p.minimum).reduce(_max)
      ..carMinimum = group.map((p) => p.carMinimum).reduce(_max)
      ..location = group
          .map((p) => p.location)
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    changes.add((before: keeper, after: after));
    for (final p in group) {
      if (p.id != keeper.id) changes.add((before: p, after: null));
    }
  }
  return changes;
}

String _key(String value) => value.trim().toUpperCase();
int _max(int a, int b) => a > b ? a : b;

bool _isUpToDate(Part part, Part product) =>
    part.name == product.name &&
    part.category == product.category &&
    _key(part.productNumber) == _key(product.sku) &&
    (product.orderNumber.isEmpty ||
        _key(part.orderNumber) == _key(product.orderNumber)) &&
    (product.imageAsset.isEmpty || part.imageAsset == product.imageAsset);

/// Preview of the switch to the shared catalogue: shows every stock part
/// with the suggested product, lets the user change or clear it and writes
/// the result in one transaction.
class CatalogMigrationPage extends StatefulWidget {
  const CatalogMigrationPage({
    super.key,
    required this.cloud,
    required this.parts,
  });

  final CloudInventory cloud;
  final List<Part> parts;

  @override
  State<CatalogMigrationPage> createState() => _CatalogMigrationPageState();
}

class _CatalogMigrationPageState extends State<CatalogMigrationPage> {
  late final Future<(List<Part>, List<MigrationRow>)> _plan =
      loadProductCatalog(cloud: widget.cloud).then((products) {
        final catalog = [...products]..sort((a, b) => a.sku.compareTo(b.sku));
        return (
          catalog,
          planCatalogMigration([
            for (final p in widget.parts) Part.fromJson(p.toJson()),
          ], catalog),
        );
      });
  bool _saving = false;

  Future<void> _apply(List<MigrationRow> rows) async {
    final changes = buildCatalogMigration(rows, widget.parts);
    final merged = changes.where((c) => c.after == null).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lager umstellen?'),
        content: Text(
          '${changes.length - merged} Lagerartikel bekommen die Angaben aus '
          'dem Katalog${merged > 0 ? ', $merged werden mit einem anderen '
                    'zusammengeführt (Mengen werden addiert)' : ''}. '
          'Die Mengen bleiben erhalten und stehen im Verlauf.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Umstellen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.cloud.applyPartChanges(changes);
      messenger.showSnackBar(
        const SnackBar(content: Text('Lager auf den Katalog umgestellt')),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Lager auf Katalog umstellen')),
    body: FutureBuilder(
      future: _plan,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Der Katalog konnte nicht geladen werden.'),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final (products, rows) = data;
        if (rows.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Alle Lagerartikel entsprechen dem Katalog.'),
            ),
          );
        }
        final count = rows.where((r) => r.target != null).length;
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Jeder Lagerartikel wird dem vorgeschlagenen Katalogprodukt '
                'zugeordnet und bekommt dessen Nummer, Name und Bild. Mengen, '
                'Mindestbestand und Lagerort bleiben. Mehrere Artikel für '
                'dasselbe Produkt werden zusammengeführt. Artikel ohne '
                'Produkt bleiben, wie sie sind.',
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, i) => _RowTile(
                  row: rows[i],
                  products: products,
                  onChanged: (target) =>
                      setState(() => rows[i].target = target),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving || count == 0
                        ? null
                        : () => _apply(rows),
                    icon: const Icon(Icons.sync_alt),
                    label: Text(
                      _saving
                          ? 'Wird umgestellt …'
                          : '$count Lagerartikel umstellen',
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.row,
    required this.products,
    required this.onChanged,
  });

  final MigrationRow row;
  final List<Part> products;
  final ValueChanged<Part?> onChanged;

  @override
  Widget build(BuildContext context) {
    final part = row.part;
    final numbers = {
      part.sku,
      part.productNumber,
      part.orderNumber,
    }.where((n) => n.isNotEmpty).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(part.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(
          '$numbers\nWerkstatt ${part.quantity} · Auto ${part.carQuantity}',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: row.target?.sku ?? '',
          decoration: InputDecoration(
            labelText: 'Katalogprodukt',
            helperText: row.reason,
          ),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('Nicht umstellen (bleibt, wie er ist)'),
            ),
            for (final p in products)
              DropdownMenuItem(
                value: p.sku,
                child: Text(
                  '${p.sku} · ${p.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (sku) => onChanged(
            sku == null || sku.isEmpty
                ? null
                : products.firstWhere((p) => p.sku == sku),
          ),
        ),
      ],
    );
  }
}
