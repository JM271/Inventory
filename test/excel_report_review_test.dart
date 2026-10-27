import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/inventory_report.dart';
import 'package:inventory/part.dart';

void main() {
  test('report separates warnings by store and reconciles every total', () {
    final parts = [
      Part(
        id: '1',
        name: 'Car low',
        category: 'Other',
        quantity: 8,
        carQuantity: 2,
        carMinimum: 3,
      ),
      Part(
        id: '2',
        name: 'Workshop low',
        category: 'Other',
        quantity: 2,
        carQuantity: 10,
        carMinimum: 3,
      ),
      Part(id: '3', name: 'Car disabled', category: 'Other', quantity: 8),
      Part(id: '4', name: 'Empty', category: 'Other'),
    ];
    final book = Excel.decodeBytes(
      buildInventoryReport(parts, DateTime.utc(2026, 10, 16)),
    );
    expect(book.tables.keys, ['Inventory']);
    final sheet = book['Inventory'];
    final rows = sheet.rows;
    expect(rows[3][1]!.value, IntCellValue(4));
    expect(rows[3][3]!.value, IntCellValue(30));
    expect(rows[3][5]!.value, IntCellValue(3));
    expect(rows[4][1]!.value, IntCellValue(18));
    expect(rows[4][3]!.value, IntCellValue(12));
    expect(rows[4][5]!.value, IntCellValue(2));
    expect(rows[4][7]!.value, IntCellValue(1));
    final detail = {
      for (final row in rows.skip(6)) row[0]!.value.toString(): row,
    };
    expect(detail['Car low']![11]!.value, TextCellValue('In stock'));
    expect(detail['Car low']![12]!.value, TextCellValue('Low stock'));
    expect(detail['Workshop low']![11]!.value, TextCellValue('Low stock'));
    expect(detail['Workshop low']![12]!.value, TextCellValue('In stock'));
    expect(detail['Car disabled']![7]!.value, TextCellValue('In stock'));
    expect(detail['Empty']![7]!.value, TextCellValue('Out of stock'));
    for (final row in detail.values) {
      final total = (row[5]!.value as IntCellValue).value;
      expect(
        total,
        (row[8]!.value as IntCellValue).value +
            (row[9]!.value as IntCellValue).value,
      );
    }
  });

  test('long descriptions and leading-zero article numbers survive export', () {
    final name = List.filled(15, 'Long product description').join(' ');
    final book = Excel.decodeBytes(
      buildInventoryReport([
        Part(
          id: '1',
          name: name,
          category: 'Other',
          sku: 'catalogue-reference',
          productNumber: '001234',
          orderNumber: '000987',
          location: '=Shelf A',
        ),
      ], DateTime.utc(2026)),
    );
    final sheet = book['Inventory'];
    expect(sheet.rows[6][0]!.value, TextCellValue(name));
    expect(sheet.rows[6][2]!.value, TextCellValue('001234'));
    expect(sheet.rows[6][3]!.value, TextCellValue('000987'));
    expect(sheet.rows[6][4]!.value, TextCellValue('=Shelf A'));
    expect(sheet.rows[6][0]!.cellStyle!.wrap, TextWrapping.WrapText);
    expect(sheet.getRowHeight(6), greaterThan(100));
  });
}
