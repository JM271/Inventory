import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inventory/main.dart';

void main() {
  testWidgets('stock history is visible and opens on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'test_stock_added_v1': true});
    await tester.pumpWidget(const InventoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Letzte Bestandsänderungen'));
    await tester.pumpAndSettle();
    expect(find.text('Recent stock changes'), findsOneWidget);
    expect(
      find.textContaining('No stock changes recorded yet.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('add stock, adjust it and reload saved inventory', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'test_stock_added_v1': true});
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
    await tester.scrollUntilVisible(
      find.text('11-speed chain'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('11-speed chain'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Use one · Werkstatt'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Use one · Werkstatt'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nachbestellen · min. 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const InventoryApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('11-speed chain'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('11-speed chain'), findsOneWidget);
    expect(find.textContaining('Nachbestellen · min. 2'), findsOneWidget);
  });
}
