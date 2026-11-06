import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/main.dart';

void main() {
  test('prices are shown as Swiss francs with apostrophe thousands', () {
    expect(formatChf(269000), "CHF 2'690.00");
    expect(formatChf(185050), "CHF 1'850.50");
    expect(formatChf(990), 'CHF 9.90');
    expect(formatChf(123456789), "CHF 1'234'567.89");
  });
}
