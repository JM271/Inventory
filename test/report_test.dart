import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventory/inventory_report.dart';
import 'package:inventory/onedrive_service.dart';
import 'package:inventory/part.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('Excel preserves SKU text, quantities and restocking status', () {
    final report = Excel.decodeBytes(
      buildInventoryReport([
        Part(
          id: '1',
          name: '=chain',
          category: 'Drivetrain',
          sku: '00123',
          location: 'A / 2',
          quantity: 2,
          minimum: 2,
        ),
        Part(id: '2', name: 'Brake pads', category: 'Brakes', quantity: 0),
      ], DateTime.utc(2026, 10, 16)),
    );
    expect(report.tables.keys, ['Inventory']);
    final rows = report['Inventory'].rows;
    expect(rows[3][3]!.value, IntCellValue(2));
    expect(rows[3][5]!.value, IntCellValue(2));
    expect(rows[6][0]!.value, TextCellValue('=chain'));
    expect(rows[6][2]!.value, TextCellValue('00123'));
    expect(rows[6][4]!.value, IntCellValue(2));
    expect(rows[6][6]!.value, TextCellValue('Low stock'));
    expect(rows[7][6]!.value, TextCellValue('Out of stock'));
  });
  test('Empty inventory still produces a valid report', () {
    final sheet = Excel.decodeBytes(
      buildInventoryReport([], DateTime.utc(2026)),
    )['Inventory'];
    expect(sheet.rows[3][1]!.value, IntCellValue(0));
    expect(sheet.rows[5][0]!.value, TextCellValue('Part name'));
  });
  test('Device sign-in obeys pending and slow-down, then uploads Excel bytes', () async {
    var polls = 0;
    final delays = <int>[];
    final bytes = Uint8List.fromList([1, 2, 3]);
    final service = OneDriveService(
      client: MockClient((request) async {
        if (request.url.host == 'login.microsoftonline.com') {
          expect(request.url.path, startsWith('/consumers/oauth2/v2.0/'));
        }
        if (request.url.path.endsWith('/devicecode')) {
          expect(request.bodyFields['scope'], contains('Files.ReadWrite'));
          return http.Response(
            jsonEncode({
              'user_code': 'ABC123',
              'device_code': 'private-code',
              'verification_uri': 'https://microsoft.com/link',
              'expires_in': 900,
              'interval': 5,
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/token')) {
          polls++;
          if (polls == 1) {
            return http.Response('{"error":"authorization_pending"}', 400);
          }
          if (polls == 2) {
            return http.Response('{"error":"slow_down"}', 400);
          }
          return http.Response(
            '{"access_token":"test-token","expires_in":3600}',
            200,
          );
        }
        if (request.method == 'GET') {
          return http.Response(
            '{"id":"folder","folder":{},"parentReference":{"driveId":"drive"}}',
            200,
          );
        }
        expect(request.method, 'PUT');
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.bodyBytes, bytes);
        expect(request.url.path, contains('report.xlsx'));
        return http.Response(
          '{"id":"file-id","webUrl":"https://onedrive.live.com/test"}',
          201,
        );
      }),
    );
    final request = await service.startSignIn('client');
    await service.finishSignIn(
      'client',
      request,
      () => false,
      wait: (d) async {
        delays.add(d.inSeconds);
      },
    );
    expect(delays, [5, 5, 10]);
    expect(service.connected, isTrue);
    expect(
      await service.upload('report.xlsx', bytes),
      Uri.parse('https://onedrive.live.com/test'),
    );
    service.dispose();
  });
  test('Denied uploads are errors and never reported as saved', () async {
    final service = OneDriveService(
      client: MockClient(
        (request) async => request.url.path.endsWith('/token')
            ? http.Response('{"access_token":"test","expires_in":3600}', 200)
            : request.method == 'GET'
            ? http.Response(
                '{"id":"folder","folder":{},"parentReference":{"driveId":"drive"}}',
                200,
              )
            : http.Response('{"error":{"code":"accessDenied"}}', 403),
      ),
    );
    await service.finishSignIn(
      'client',
      DeviceSignIn(
        'code',
        'private',
        Uri.parse('https://microsoft.com/link'),
        DateTime.now().add(const Duration(minutes: 1)),
        0,
      ),
      () => false,
      wait: (_) async {},
    );
    await expectLater(
      service.upload('report.xlsx', Uint8List(0)),
      throwsA(
        isA<OneDriveException>().having(
          (e) => e.message,
          'message',
          contains('denied'),
        ),
      ),
    );
    service.dispose();
  });
  test('Missing tenant error identifies the setup problem', () async {
    final service = OneDriveService(
      client: MockClient(
        (_) async => http.Response(
          '{"error":"invalid_request","error_codes":[50059]}',
          400,
        ),
      ),
    );
    await expectLater(
      service.startSignIn('client'),
      throwsA(
        isA<OneDriveException>().having(
          (e) => e.message,
          'message',
          allOf(contains('AADSTS50059'), contains('Directory (tenant) ID')),
        ),
      ),
    );
    service.dispose();
  });

  for (final entry in {
    401: 'expired',
    403: 'denied',
    404: 'could not be found',
    429: 'Wait 12 seconds',
    500: 'temporarily unavailable',
    507: 'storage is full',
  }.entries) {
    test(
      'HTTP ${entry.key} gives recovery guidance even without JSON',
      () async {
        final service = OneDriveService(
          client: MockClient(
            (_) async => http.Response(
              'not json',
              entry.key,
              headers: {'retry-after': '12'},
            ),
          ),
        );
        await expectLater(
          service.startSignIn('client'),
          throwsA(
            isA<OneDriveException>().having(
              (e) => e.message,
              'message',
              contains(entry.value),
            ),
          ),
        );
        service.dispose();
      },
    );
  }
  test('Network errors and timeouts give clear messages', () async {
    final network = OneDriveService(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      network.startSignIn('client'),
      throwsA(
        isA<OneDriveException>().having(
          (e) => e.message,
          'message',
          contains('internet connection'),
        ),
      ),
    );
    network.dispose();
    final timeout = OneDriveService(
      client: MockClient((_) async => throw TimeoutException('timeout')),
    );
    await expectLater(
      timeout.startSignIn('client'),
      throwsA(
        isA<OneDriveException>().having(
          (e) => e.message,
          'message',
          contains('too long'),
        ),
      ),
    );
    timeout.dispose();
  });
  test(
    'Incomplete Microsoft response is rejected before displaying a code',
    () async {
      final service = OneDriveService(
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(
        service.startSignIn('client'),
        throwsA(
          isA<OneDriveException>().having(
            (e) => e.message,
            'message',
            contains('incomplete'),
          ),
        ),
      );
      service.dispose();
    },
  );
  test('Cancelled sign-in never acquires a token', () async {
    final service = OneDriveService(
      client: MockClient((_) async => throw StateError('Must not poll')),
    );
    await service.finishSignIn(
      'client',
      DeviceSignIn(
        'code',
        'private',
        Uri.parse('https://microsoft.com/link'),
        DateTime.now().add(const Duration(minutes: 1)),
        0,
      ),
      () => true,
      wait: (_) async {},
    );
    expect(service.connected, isFalse);
    service.dispose();
  });
}
