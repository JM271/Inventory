import 'product_identifiers.dart';

enum StockSite { workshop, car, garage }

extension StockSiteLabel on StockSite {
  String get label => switch (this) {
    StockSite.workshop => 'Poya',
    StockSite.car => 'Auto',
    StockSite.garage => 'Garage',
  };
}

class Part {
  Part({
    required this.id,
    required this.name,
    required this.category,
    this.sku = '',
    String? productNumber,
    String? orderNumber,
    this.imageAsset = '',
    this.location = '',
    this.quantity = 0,
    this.minimum = 2,
    this.carQuantity = 0,
    this.carMinimum = 0,
    this.garageQuantity = 0,
    this.garageMinimum = 0,
  }) : _productNumber = productNumber?.trim(),
       _orderNumber = orderNumber?.trim();
  final String id;
  // Keep the legacy SKU stable: saved inventory and cloud catalogue keys use it.
  String name, category, sku, location, imageAsset;
  String? _productNumber, _orderNumber;

  String get _legacySku => sku.trim().toUpperCase();

  // Known catalogue SKUs are supplier references. Other legacy/custom SKUs
  // retain their original interpretation as the user's own product ID.
  String get productNumber =>
      _productNumber ?? legacySupplierProductNumbers[_legacySku] ?? sku;
  set productNumber(String value) => _productNumber = value.trim();
  String get orderNumber =>
      _orderNumber ??
      (legacySupplierProductNumbers.containsKey(_legacySku) ? sku : '');
  set orderNumber(String value) => _orderNumber = value.trim();
  String get productIdentification => productNumber;
  String get supplierOrderNumber => orderNumber;
  int quantity, minimum, carQuantity, carMinimum, garageQuantity, garageMinimum;
  int get totalQuantity => quantity + carQuantity + garageQuantity;
  int quantityAt(StockSite site) => switch (site) {
    StockSite.workshop => quantity,
    StockSite.car => carQuantity,
    StockSite.garage => garageQuantity,
  };
  int minimumAt(StockSite site) => switch (site) {
    StockSite.workshop => minimum,
    StockSite.car => carMinimum,
    StockSite.garage => garageMinimum,
  };

  /// Poya (the workshop) is always checked; at the other sites a minimum of 0
  /// turns the restock warning off.
  bool lowAt(StockSite site) => site == StockSite.workshop
      ? quantity <= minimum
      : minimumAt(site) > 0 && quantityAt(site) <= minimumAt(site);
  bool get low => StockSite.values.any(lowAt);
  void adjustAt(StockSite site, int delta) {
    if (quantityAt(site) + delta < 0) throw ArgumentError('Insufficient stock');
    switch (site) {
      case StockSite.workshop:
        quantity += delta;
      case StockSite.car:
        carQuantity += delta;
      case StockSite.garage:
        garageQuantity += delta;
    }
  }

  void transfer(StockSite from, StockSite to, int amount) {
    if (from == to || amount <= 0 || amount > quantityAt(from)) {
      throw ArgumentError('Invalid transfer quantity');
    }
    adjustAt(from, -amount);
    adjustAt(to, amount);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'sku': sku,
    'productNumber': productNumber,
    'orderNumber': orderNumber,
    'imageAsset': imageAsset,
    'location': location,
    'quantity': quantity,
    'minimum': minimum,
    'carQuantity': carQuantity,
    'carMinimum': carMinimum,
    'garageQuantity': garageQuantity,
    'garageMinimum': garageMinimum,
  };
  factory Part.fromJson(Map<String, dynamic> j) => Part(
    id: j['id'],
    name: j['name'],
    category: j['category'],
    sku: j['sku'],
    productNumber: j['productNumber'] as String?,
    // The first dual-number version wrote empty orderNumber values to legacy
    // records. Resolve those once; later explicit blank edits stay blank.
    orderNumber: j.containsKey('productNumber')
        ? j['orderNumber'] as String?
        : (j['orderNumber'] as String?)?.isNotEmpty == true
        ? j['orderNumber'] as String
        : null,
    imageAsset: j['imageAsset'] as String? ?? '',
    location: j['location'],
    quantity: j['quantity'],
    minimum: j['minimum'],
    carQuantity: j['carQuantity'] as int? ?? 0,
    carMinimum: j['carMinimum'] as int? ?? 0,
    garageQuantity: j['garageQuantity'] as int? ?? 0,
    garageMinimum: j['garageMinimum'] as int? ?? 0,
  );
}
