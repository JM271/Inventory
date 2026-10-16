import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inventory/main.dart';

void main() {
  testWidgets('add stock, adjust it and reload saved inventory', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const InventoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Part name'),
      '11-speed chain',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Quantity'), '3');
    await tester.ensureVisible(find.text('Save part'));
    await tester.tap(find.text('Save part'));
    await tester.pumpAndSettle();
    expect(find.text('11-speed chain'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Use one'));
    await tester.tap(find.byTooltip('Use one'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Low stock · min. 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const InventoryApp());
    await tester.pumpAndSettle();
    expect(find.text('11-speed chain'), findsOneWidget);
    expect(find.textContaining('Low stock · min. 2'), findsOneWidget);
  });
}
