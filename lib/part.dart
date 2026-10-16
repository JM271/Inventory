enum StockSite { workshop, car }

extension StockSiteLabel on StockSite {
  String get label => this == StockSite.workshop ? 'Werkstatt' : 'Auto';
}

class Part {
  Part({
    required this.id,
    required this.name,
    required this.category,
    this.sku = '',
    this.imageAsset = '',
    this.location = '',
    this.quantity = 0,
    this.minimum = 2,
    this.carQuantity = 0,
    this.carMinimum = 0,
  });
  final String id;
  String name, category, sku, location, imageAsset;
  int quantity, minimum, carQuantity, carMinimum;
  int get totalQuantity => quantity + carQuantity;
  int quantityAt(StockSite site) =>
      site == StockSite.workshop ? quantity : carQuantity;
  int minimumAt(StockSite site) =>
      site == StockSite.workshop ? minimum : carMinimum;
  bool lowAt(StockSite site) => site == StockSite.workshop
      ? quantity <= minimum
      : carMinimum > 0 && carQuantity <= carMinimum;
  bool get low => lowAt(StockSite.workshop) || lowAt(StockSite.car);
  void adjustAt(StockSite site, int delta) {
    if (quantityAt(site) + delta < 0) throw ArgumentError('Insufficient stock');
    if (site == StockSite.workshop) {
      quantity += delta;
    } else {
      carQuantity += delta;
    }
  }

  void transfer(StockSite from, int amount) {
    if (amount <= 0 || amount > quantityAt(from)) {
      throw ArgumentError('Invalid transfer quantity');
    }
    adjustAt(from, -amount);
    adjustAt(
      from == StockSite.workshop ? StockSite.car : StockSite.workshop,
      amount,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'sku': sku,
    'imageAsset': imageAsset,
    'location': location,
    'quantity': quantity,
    'minimum': minimum,
    'carQuantity': carQuantity,
    'carMinimum': carMinimum,
  };
  factory Part.fromJson(Map<String, dynamic> j) => Part(
    id: j['id'],
    name: j['name'],
    category: j['category'],
    sku: j['sku'],
    imageAsset: j['imageAsset'] as String? ?? '',
    location: j['location'],
    quantity: j['quantity'],
    minimum: j['minimum'],
    carQuantity: j['carQuantity'] as int? ?? 0,
    carMinimum: j['carMinimum'] as int? ?? 0,
  );
}
