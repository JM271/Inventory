import 'dart:convert';

import 'part.dart';
export 'part.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const InventoryApp());
}

const categories = [
  'Drivetrain',
  'Brakes',
  'Wheels & tyres',
  'Cockpit',
  'Tools',
  'Consumables',
  'Other',
];
const ink = Color(0xFF172C29);
const green = Color(0xFF286653);

class InventoryApp extends StatelessWidget {
  const InventoryApp({super.key});
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
    home: const InventoryPage(),
  );
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  List<Part> parts = [];
  String query = '', category = 'All parts';
  bool lowOnly = false, loading = true;
  SharedPreferences? prefs;
  String? storageError;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      prefs = await SharedPreferences.getInstance();
      final raw = prefs!.getString('workshop_parts');
      if (raw != null) {
        parts = (jsonDecode(raw) as List).map((j) => Part.fromJson(j)).toList();
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
    final result = await showModalBottomSheet<Part>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PartEditor(part: part),
    );
    if (result == null || !mounted) {
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

  Future<void> adjust(Part part, int delta) async {
    if (part.quantity + delta < 0) {
      return;
    }
    setState(() => part.quantity += delta);
    await save();
  }

  Future<void> remove(Part part) async {
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
                  (!lowOnly || p.low) &&
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
        title: const Row(
          children: [
            Icon(Icons.pedal_bike, color: green, size: 30),
            SizedBox(width: 10),
            Text(
              'spoke',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -1),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 20),
            child: Text(
              'WORKSHOP',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
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
                              '${parts.fold<int>(0, (sum, p) => sum + p.quantity)}',
                              'Units in stock',
                            ),
                          ),
                          Expanded(
                            child: metric(
                              '${parts.where((p) => p.low).length}',
                              'Need restocking',
                              accent: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
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
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFFEAF0E9),
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
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      p.low
                                          ? '● ${p.quantity == 0 ? 'Out of stock' : 'Low stock'} · min. ${p.minimum}'
                                          : 'In stock · min. ${p.minimum}',
                                      style: TextStyle(
                                        color: p.low
                                            ? const Color(0xFFA55C1B)
                                            : green,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton.outlined(
                                    tooltip: 'Use one',
                                    onPressed: p.quantity == 0
                                        ? null
                                        : () => adjust(p, -1),
                                    icon: const Icon(Icons.remove, size: 18),
                                  ),
                                  SizedBox(
                                    width: 44,
                                    child: Text(
                                      '${p.quantity}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton.outlined(
                                    tooltip: 'Receive one',
                                    onPressed: () => adjust(p, 1),
                                    icon: const Icon(Icons.add, size: 18),
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
  const PartEditor({super.key, this.part});
  final Part? part;
  @override
  State<PartEditor> createState() => _PartEditorState();
}

class _PartEditorState extends State<PartEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, sku, location, quantity, minimum;
  late String category;
  @override
  void initState() {
    super.initState();
    final p = widget.part;
    name = TextEditingController(text: p?.name);
    sku = TextEditingController(text: p?.sku);
    location = TextEditingController(text: p?.location);
    quantity = TextEditingController(text: '${p?.quantity ?? 0}');
    minimum = TextEditingController(text: '${p?.minimum ?? 2}');
    category = p?.category ?? categories.first;
  }

  @override
  void dispose() {
    for (final c in [name, sku, location, quantity, minimum]) {
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
            field('Part name', name, required: true),
            DropdownButtonFormField<String>(
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: field('Quantity', quantity, number: true)),
                const SizedBox(width: 12),
                Expanded(child: field('Minimum stock', minimum, number: true)),
              ],
            ),
            const Text(
              'Parts at or below the minimum appear in Low stock.',
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
                          DateTime.now().microsecondsSinceEpoch.toString(),
                      name: name.text.trim(),
                      category: category,
                      sku: sku.text.trim(),
                      location: location.text.trim(),
                      quantity: int.parse(quantity.text),
                      minimum: int.parse(minimum.text),
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
