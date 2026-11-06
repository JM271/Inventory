import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'part.dart';

Uint8List buildInventoryReport(List<Part> parts, DateTime generatedAt) {
  final excel = Excel.createExcel();
  final sheet = excel['Inventory'];
  excel.delete('Sheet1');
  excel.setDefaultSheet('Inventory');
  void row(List<CellValue> values) => sheet.appendRow(values);
  TextCellValue text(String value) => TextCellValue(value);
  row([text('Spoke · Poya, car and garage inventory')]);
  row([text('Generated (UTC)'), text(generatedAt.toUtc().toIso8601String())]);
  row([text('Scope'), text('All inventory, regardless of active filters')]);
  row([
    text('Part types'),
    IntCellValue(parts.length),
    text('Total units'),
    IntCellValue(parts.fold(0, (n, p) => n + p.totalQuantity)),
    text('Need restocking'),
    IntCellValue(parts.where((p) => p.low).length),
  ]);
  row([
    text('Poya units'),
    IntCellValue(parts.fold<int>(0, (n, p) => n + p.quantity)),
    text('Car units'),
    IntCellValue(parts.fold<int>(0, (n, p) => n + p.carQuantity)),
    text('Garage units'),
    IntCellValue(parts.fold<int>(0, (n, p) => n + p.garageQuantity)),
    text('Poya restock'),
    IntCellValue(parts.where((p) => p.lowAt(StockSite.workshop)).length),
    text('Car restock'),
    IntCellValue(parts.where((p) => p.lowAt(StockSite.car)).length),
    text('Garage restock'),
    IntCellValue(parts.where((p) => p.lowAt(StockSite.garage)).length),
  ]);
  row(
    [
      'Part name',
      'Category',
      'Our product ID',
      'Supplier order number',
      'Location',
      'Total quantity',
      'Minimum Poya',
      'Stock status',
      'Poya quantity',
      'Car quantity',
      'Minimum car',
      'Garage quantity',
      'Minimum garage',
      'Poya status',
      'Car status',
      'Garage status',
    ].map(text).toList(),
  );
  final sorted = [...parts]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  for (final p in sorted) {
    row([
      text(p.name),
      text(p.category),
      text(p.productIdentification),
      text(p.supplierOrderNumber),
      text(p.location),
      IntCellValue(p.totalQuantity),
      IntCellValue(p.minimum),
      text(
        p.totalQuantity == 0
            ? 'Out of stock'
            : p.low
            ? 'Low stock'
            : 'In stock',
      ),
      IntCellValue(p.quantity),
      IntCellValue(p.carQuantity),
      IntCellValue(p.carMinimum),
      IntCellValue(p.garageQuantity),
      IntCellValue(p.garageMinimum),
      text(
        p.quantity == 0
            ? 'Out of stock'
            : p.lowAt(StockSite.workshop)
            ? 'Low stock'
            : 'In stock',
      ),
      text(
        p.carQuantity == 0
            ? 'Out of stock'
            : p.lowAt(StockSite.car)
            ? 'Low stock'
            : 'In stock',
      ),
      text(
        p.garageQuantity == 0
            ? 'Out of stock'
            : p.lowAt(StockSite.garage)
            ? 'Low stock'
            : 'In stock',
      ),
    ]);
  }
  const widths = [
    44.0,
    22.0,
    24.0,
    26.0,
    28.0,
    16.0,
    20.0,
    20.0,
    20.0,
    18.0,
    18.0,
    18.0,
    18.0,
    20.0,
    20.0,
    20.0,
  ];
  sheet.setRowHeight(5, 36);
  for (var c = 0; c < widths.length; c++) {
    sheet.setColumnWidth(c, widths[c]);
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 5))
        .cellStyle = CellStyle(
      bold: true,
      textWrapping: TextWrapping.WrapText,
      backgroundColorHex: ExcelColor.fromHexString('#000000'),
      fontColorHex: ExcelColor.white,
    );
  }
  for (var r = 6; r < sheet.maxRows; r++) {
    var lines = 1;
    for (var c = 0; c < widths.length; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
      );
      cell.cellStyle = CellStyle(
        textWrapping: TextWrapping.WrapText,
        verticalAlign: VerticalAlign.Top,
        fontSize: 11,
      );
      final value = cell.value;
      if (value is TextCellValue) {
        // Leave room for word wrapping and explicit newlines in descriptions.
        final estimated = value.value.text!
            .split('\n')
            .fold<int>(
              0,
              (sum, line) =>
                  sum + (line.length / (widths[c] * .8)).ceil().clamp(1, 1000),
            );
        if (estimated > lines) lines = estimated;
      }
    }
    sheet.setRowHeight(r, 16.0 * lines + 8);
  }
  sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
    bold: true,
    fontSize: 18,
  );
  return Uint8List.fromList(excel.encode()!);
}
