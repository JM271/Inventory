import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'part.dart';

String _pdfText(String value) => value
    .replaceAll('，', ',')
    .replaceAll('：', ':')
    .replaceAll('（', '(')
    .replaceAll('）', ')');

Future<Uint8List> buildInventoryPdf(
  List<Part> parts,
  DateTime generatedAt,
) async {
  final document = pw.Document(
    title: 'Inventory - Lagerbericht',
    author: 'Spoke',
  );
  final sorted = [...parts]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final date = generatedAt.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final timestamp =
      '${two(date.day)}.${two(date.month)}.${date.year} ${two(date.hour)}:${two(date.minute)}';
  final green = PdfColor.fromHex('#286653');
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(30),
      maxPages: 1000,
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      ),
      header: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'spoke | Lagerbericht',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: green,
              ),
            ),
            pw.Text(timestamp, style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Seite ${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      build: (_) => [
        pw.Text(
          '${parts.length} Artikel  |  ${parts.fold<int>(0, (sum, p) => sum + p.quantity)} Stück  |  ${parts.where((p) => p.low).length} nachbestellen',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Vollständiger Lagerbestand, unabhängig von Suchfiltern. [TEST] kennzeichnet Testdaten.',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 14),
        if (parts.isEmpty) pw.Text('Keine Lagerartikel vorhanden.'),
        if (parts.isNotEmpty)
          pw.TableHelper.fromTextArray(
            headers: [
              'Artikel / SKU',
              'Kategorie / Lagerort',
              'Bestand',
              'Min.',
              'Status',
            ],
            data: [
              for (final p in sorted)
                [
                  _pdfText('${p.name}\n${p.sku}'),
                  _pdfText('${p.category}\n${p.location}'),
                  '${p.quantity}',
                  '${p.minimum}',
                  p.quantity == 0
                      ? 'Nicht am Lager'
                      : p.low
                      ? 'Nachbestellen'
                      : 'Am Lager',
                ],
            ],
            columnWidths: {
              0: const pw.FlexColumnWidth(4),
              1: const pw.FlexColumnWidth(2.4),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(.7),
              4: const pw.FlexColumnWidth(1.5),
            },
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
            headerDecoration: pw.BoxDecoration(color: green),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.all(6),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            cellAlignments: {
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
          ),
      ],
    ),
  );
  return document.save();
}
