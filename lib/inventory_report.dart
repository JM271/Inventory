import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'part.dart';

Uint8List buildInventoryReport(List<Part> parts, DateTime generatedAt) {
  final excel = Excel.createExcel();
  final sheet = excel['Inventory'];
  excel.delete('Sheet1');
  void row(List<CellValue> values) => sheet.appendRow(values);
  TextCellValue text(String value) => TextCellValue(value);
  row([text('Spoke · Workshop inventory')]);
  row([text('Generated (UTC)'), text(generatedAt.toUtc().toIso8601String())]);
  row([text('Scope'), text('All inventory, regardless of active filters')]);
  row([
    text('Part types'),
    IntCellValue(parts.length),
    text('Total units'),
    IntCellValue(parts.fold(0, (n, p) => n + p.quantity)),
    text('Need restocking'),
    IntCellValue(parts.where((p) => p.low).length),
  ]);
  row([text('')]);
  row(
    [
      'Part name',
      'Category',
      'SKU / part number',
      'Location',
      'Quantity',
      'Minimum stock',
      'Stock status',
    ].map(text).toList(),
  );
  final sorted = [...parts]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  for (final p in sorted) {
    row([
      text(p.name),
      text(p.category),
      text(p.sku),
      text(p.location),
      IntCellValue(p.quantity),
      IntCellValue(p.minimum),
      text(
        p.quantity == 0
            ? 'Out of stock'
            : p.low
            ? 'Low stock'
            : 'In stock',
      ),
    ]);
  }
  for (var c = 0; c < 7; c++) {
    sheet.setColumnWidth(c, [32.0, 22.0, 24.0, 28.0, 14.0, 18.0, 20.0][c]);
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 5))
        .cellStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#286653'),
      fontColorHex: ExcelColor.white,
    );
  }
  sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
    bold: true,
    fontSize: 18,
  );
  return Uint8List.fromList(excel.encode()!);
}
