import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/main.dart';
import 'package:inventory/inventory_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('legacy stock stays in workshop and new fields survive round trip', () {
    final legacy =
        Part(
            id: '1',
            name: 'Chain',
            category: 'Drivetrain',
            quantity: 8,
          ).toJson()
          ..remove('carQuantity')
          ..remove('carMinimum');
    final part = Part.fromJson(legacy);
    expect(part.quantity, 8);
    expect(part.carQuantity, 0);
    expect(part.lowAt(StockSite.car), isFalse);
    part.transfer(StockSite.workshop, 3);
    part.carMinimum = 3;
    final reloaded = Part.fromJson(part.toJson());
    expect(reloaded.quantity, 5);
    expect(reloaded.carQuantity, 3);
    expect(reloaded.totalQuantity, 8);
    expect(reloaded.lowAt(StockSite.workshop), isFalse);
    expect(reloaded.lowAt(StockSite.car), isTrue);
    reloaded.transfer(StockSite.car, 2);
    expect(reloaded.quantity, 7);
    expect(reloaded.carQuantity, 1);
    for (final amount in [0, -1, 8]) {
      expect(
        () => reloaded.transfer(StockSite.workshop, amount),
        throwsArgumentError,
      );
      expect(reloaded.totalQuantity, 8);
    }
    expect(() => reloaded.adjustAt(StockSite.car, -2), throwsArgumentError);
    expect(reloaded.carQuantity, 1);
  });

  test('Excel includes both locations and combined totals', () {
    final p = Part(
      id: '1',
      name: 'Chain',
      category: 'Drivetrain',
      quantity: 8,
      carQuantity: 2,
      carMinimum: 3,
    );
    final sheet = Excel.decodeBytes(
      buildInventoryReport([p], DateTime.utc(2026)),
    )['Inventory'];
    expect(sheet.rows[3][3]!.value, IntCellValue(10));
    expect(sheet.rows[6][4]!.value, IntCellValue(10));
    expect(sheet.rows[6][7]!.value, IntCellValue(8));
    expect(sheet.rows[6][8]!.value, IntCellValue(2));
    expect(sheet.rows[6][9]!.value, IntCellValue(3));
  });

  testWidgets('transfer rejects excess stock and persists both sites', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'test_stock_added_v1': true,
      'workshop_parts': jsonEncode([
        Part(
          id: '1',
          name: 'Chain',
          category: 'Drivetrain',
          quantity: 8,
        ).toJson(),
      ]),
    });
    await tester.pumpWidget(const InventoryApp());
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Umlagern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Umlagern'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Menge'), '9');
    await tester.tap(find.widgetWithText(FilledButton, 'Umlagern'));
    await tester.pumpAndSettle();
    expect(find.text('Menge zwischen 1 und 8 eingeben'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Menge'), '3');
    await tester.tap(find.widgetWithText(FilledButton, 'Umlagern'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final stored = Part.fromJson(
      (jsonDecode(prefs.getString('workshop_parts')!) as List).single,
    );
    expect(stored.quantity, 5);
    expect(stored.carQuantity, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const InventoryApp());
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<StockSite?>),
        matching: find.text('Auto'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Use one · Werkstatt'), findsNothing);
    expect(find.byTooltip('Use one · Auto'), findsOneWidget);
  });
}
