import 'dart:convert';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('one tap opens a PDF without Microsoft sign-in', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
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
          quantity: 3,
        ).toJson(),
        Part(id: '2', name: 'Pads', category: 'Brakes', quantity: 7).toJson(),
      ]),
    });
    Uint8List? pdf;
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryPage(
          openPdfReport: (bytes) async {
            pdf = bytes;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Chain');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(pdf, isNotNull);
    expect(ascii.decode(pdf!.take(5).toList()), '%PDF-');
    expect(find.byType(AlertDialog), findsNothing);
  });
}
