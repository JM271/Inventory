class Part {
  Part({
    required this.id,
    required this.name,
    required this.category,
    this.sku = '',
    this.location = '',
    this.quantity = 0,
    this.minimum = 2,
  });
  final String id;
  String name, category, sku, location;
  int quantity, minimum;
  bool get low => quantity <= minimum;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'sku': sku,
    'location': location,
    'quantity': quantity,
    'minimum': minimum,
  };
  factory Part.fromJson(Map<String, dynamic> j) => Part(
    id: j['id'],
    name: j['name'],
    category: j['category'],
    sku: j['sku'],
    location: j['location'],
    quantity: j['quantity'],
    minimum: j['minimum'],
  );
}
