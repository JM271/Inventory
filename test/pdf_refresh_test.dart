import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/pdf_report_page.dart';

PdfReportSnapshot snapshot(String value, int second) => PdfReportSnapshot(
  bytes: Uint8List.fromList(utf8.encode(value)),
  filename: '$value.pdf',
  generatedAt: DateTime(2026, 10, 16, 12, 0, second),
);

void main() {
  testWidgets('refresh replaces the displayed report with current stock', (
    tester,
  ) async {
    var quantity = 8;
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PdfReportPage(
          initialReport: snapshot('Werkstatt 8 / Auto 0', 0),
          onRefresh: () async {
            calls++;
            return snapshot('Werkstatt $quantity / Auto 3', calls);
          },
          previewBuilder: (report) =>
              Text('${report.filename}: ${utf8.decode(report.bytes)}'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    quantity = 5;
    await tester.tap(find.byTooltip('PDF aktualisieren'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Werkstatt 5 / Auto 3'), findsOneWidget);
    expect(find.textContaining('Werkstatt 8 / Auto 0'), findsNothing);
    expect(find.textContaining('12:00:01'), findsOneWidget);
    expect(calls, 1);
    quantity = 2;
    await tester.tap(find.byTooltip('PDF aktualisieren'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Werkstatt 2 / Auto 3'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('failed refresh preserves the previous report and allows retry', (
    tester,
  ) async {
    var fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: PdfReportPage(
          initialReport: snapshot('previous', 0),
          onRefresh: () async {
            if (fail) throw StateError('failure');
            return snapshot('current', 1);
          },
          previewBuilder: (report) => Text(utf8.decode(report.bytes)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('PDF aktualisieren'));
    await tester.pumpAndSettle();
    expect(find.text('previous'), findsOneWidget);
    expect(
      find.textContaining('Aktualisierung fehlgeschlagen'),
      findsOneWidget,
    );
    fail = false;
    await tester.tap(find.byTooltip('PDF aktualisieren'));
    await tester.pumpAndSettle();
    expect(find.text('current'), findsOneWidget);
  });
}
