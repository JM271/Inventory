import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/stock_changes_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('history shows saved quantities, actor and local timestamp', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'stock_changes_v1': jsonEncode([
        {
          'name': 'Chain',
          'productNumber': '0012',
          'action': 'Changed',
          'beforeWorkshop': 5,
          'afterWorkshop': 3,
          'beforeCar': 1,
          'afterCar': 3,
          'uid': 'This device',
          'createdAt': '2026-10-27T12:00:00Z',
        },
      ]),
    });
    await tester.pumpWidget(const MaterialApp(home: StockChangesPage()));
    await tester.pumpAndSettle();
    expect(find.text('Chain'), findsOneWidget);
    expect(find.text('Werkstatt: 5 → 3'), findsOneWidget);
    expect(find.text('Auto: 1 → 3'), findsOneWidget);
    expect(find.text('User: This device'), findsOneWidget);
  });
  testWidgets('empty history explains when recording starts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: StockChangesPage()));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No stock changes recorded yet.'),
      findsOneWidget,
    );
  });
}
