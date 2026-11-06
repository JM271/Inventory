import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/cloud_inventory.dart';
import 'package:inventory/part.dart';
import 'package:inventory/stock_changes_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> change(
  String name, {
  String partId = 'p1',
  String action = 'Adjusted',
  List<int> before = const [5, 0, 0],
  List<int> after = const [4, 0, 0],
  String uid = 'This device',
  String? email,
  required String at,
}) => {
  'partId': partId,
  'name': name,
  'productNumber': '',
  'action': action,
  'beforeWorkshop': before[0],
  'afterWorkshop': after[0],
  'beforeCar': before[1],
  'afterCar': after[1],
  'beforeGarage': before[2],
  'afterGarage': after[2],
  'uid': uid,
  'email': ?email,
  'createdAt': at,
};

StockChange parsed(Map<String, dynamic> c) => StockChange.fromMap(c);

void main() {
  group('summary', () {
    test('shows only the sites that changed', () {
      expect(
        parsed(change('Chain', at: '2026-11-06T10:00:00Z')).summary,
        'Poya −1',
      );
      expect(
        parsed(
          change(
            'Chain',
            before: [5, 1, 0],
            after: [3, 3, 0],
            at: '2026-11-06T10:00:00Z',
          ),
        ).summary,
        'Poya → Auto · 2',
      );
      expect(
        parsed(
          change(
            'Chain',
            action: 'Added',
            before: [0, 0, 0],
            after: [4, 0, 1],
            at: '2026-11-06T10:00:00Z',
          ),
        ).summary,
        'Neu angelegt · Poya 4 · Garage 1',
      );
    });

    test('taps by one person on one part within minutes are merged', () {
      final rows = [
        change(
          'Chain',
          before: [3, 0, 0],
          after: [2, 0, 0],
          at: '2026-11-06T10:08:00Z',
        ),
        change(
          'Chain',
          before: [4, 0, 0],
          after: [3, 0, 0],
          at: '2026-11-06T10:04:00Z',
        ),
        change(
          'Chain',
          before: [5, 0, 0],
          after: [4, 0, 0],
          at: '2026-11-06T10:00:00Z',
        ),
        // Too long before the last tap: its own entry.
        change(
          'Chain',
          before: [6, 0, 0],
          after: [5, 0, 0],
          at: '2026-11-06T09:00:00Z',
        ),
        // Other person: its own entry.
        change(
          'Chain',
          uid: 'bob',
          before: [7, 0, 0],
          after: [6, 0, 0],
          at: '2026-11-06T08:59:00Z',
        ),
      ].map(parsed).toList();
      final grouped = groupChanges(rows);
      expect(grouped.map((c) => c.summary), ['Poya −3', 'Poya −1', 'Poya −1']);
      expect(grouped.first.count, 3);
    });
  });

  testWidgets('history reads as one line per change under day headings', (
    tester,
  ) async {
    final today = DateTime.now().toUtc().toIso8601String();
    SharedPreferences.setMockInitialValues({
      'stock_changes_v1': jsonEncode([
        change('Chain', before: [5, 1, 0], after: [3, 3, 0], at: today),
        change('Brake pads', partId: 'p2', at: '2025-03-04T12:00:00Z'),
      ]),
    });
    await tester.pumpWidget(const MaterialApp(home: StockChangesPage()));
    await tester.pumpAndSettle();
    expect(find.text('Heute'), findsOneWidget);
    expect(find.text('Di. 4. März 2025'), findsOneWidget);
    expect(find.text('Poya → Auto · 2 · Dieses Gerät'), findsOneWidget);
    expect(find.text('Poya −1 · Dieses Gerät'), findsOneWidget);
  });

  testWidgets('filters narrow the list by site and kind', (tester) async {
    SharedPreferences.setMockInitialValues({
      'stock_changes_v1': jsonEncode([
        change('Chain', at: '2026-11-06T10:00:00Z'),
        change(
          'Battery',
          partId: 'p2',
          before: [0, 0, 1],
          after: [0, 0, 3],
          at: '2026-11-06T09:00:00Z',
        ),
      ]),
    });
    await tester.pumpWidget(const MaterialApp(home: StockChangesPage()));
    await tester.pumpAndSettle();
    expect(find.text('Chain'), findsOneWidget);
    expect(find.text('Battery'), findsOneWidget);

    await tester.tap(find.text('Ort: Alle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garage').last);
    await tester.pumpAndSettle();
    expect(find.text('Chain'), findsNothing);
    expect(find.text('Battery'), findsOneWidget);

    await tester.tap(find.text('Art: Alle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entnommen').last);
    await tester.pumpAndSettle();
    expect(find.text('Keine Änderungen für diese Filter.'), findsOneWidget);
  });

  testWidgets('cloud entries show the person and open their part', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final alice = CloudInventory(db, 'alice', email: 'alice@molenstraat.ch');
    final part = Part(id: 'chain', name: 'Chain', category: 'Drivetrain');
    part.quantity = 3;
    await alice.savePart(part);
    await CloudInventory(db, 'bob').adjust('chain', StockSite.workshop, -1);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: StockChangesPage(
          cloud: alice,
          partId: 'chain',
          partName: 'Chain',
          onOpenPart: opened.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Verlauf · Chain'), findsOneWidget);
    expect(find.text('Neu angelegt · Poya 3 · alice'), findsOneWidget);
    // Bob saved no email and only admins can look him up.
    expect(find.text('Poya −1 · Unbekannt'), findsOneWidget);
    await tester.tap(find.text('Poya −1 · Unbekannt'));
    expect(opened, ['chain']);
  });

  testWidgets('empty history explains when recording starts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: StockChangesPage()));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Noch keine Bestandsänderungen.'),
      findsOneWidget,
    );
  });
}
