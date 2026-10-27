import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/main.dart';

void main() {
  testWidgets('manual variant identifiers preserve saved inventory and key', (
    tester,
  ) async {
    final original = Part(
      id: 'saved-controller',
      name: 'Controller',
      category: 'Electrics',
      sku: 'OXV8-02',
      quantity: 7,
      minimum: 3,
      carQuantity: 2,
      carMinimum: 1,
      location: 'Shelf B',
    );
    Part? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await Navigator.of(context).push<Part>(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(body: PartEditor(part: original)),
                  ),
                );
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final ownField = find.widgetWithText(TextFormField, 'Our product ID');
    expect(tester.widget<TextFormField>(ownField).controller!.text, isEmpty);
    expect(find.widgetWithText(TextFormField, 'OXV8-02'), findsOneWidget);
    await tester.enterText(ownField, ' MS-SP-3011 ');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Supplier order number'),
      ' OXV8-02 ',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.ensureVisible(find.text('Save part'));
    await tester.tap(find.text('Save part'));
    await tester.pumpAndSettle();

    final restored = Part.fromJson(saved!.toJson());
    expect(restored.productIdentification, 'MS-SP-3011');
    expect(restored.supplierOrderNumber, 'OXV8-02');
    expect(restored.sku, original.sku);
    expect(restored.id, original.id);
    expect(restored.quantity, original.quantity);
    expect(restored.carQuantity, original.carQuantity);
    expect(restored.minimum, original.minimum);
    expect(restored.carMinimum, original.carMinimum);
    expect(restored.location, original.location);
  });
}
