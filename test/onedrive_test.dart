import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventory/onedrive_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('security defaults guidance survives multiple codes and HTTP 403', () {
    final service = OneDriveService();
    addTearDown(service.dispose);
    final error = service.responseError(http.Response('', 403), {
      'error_codes': [999999, 530035],
      'error_description': 'private account details',
    });
    expect(error.message, contains('Security Defaults'));
    expect(error.message, contains('AADSTS530035'));
    expect(error.message, isNot(contains('private account details')));
  });

  test('browser request error is extracted without exposing server text', () {
    final service = OneDriveService();
    addTearDown(service.dispose);
    final error = service.responseError(http.Response('', 400), {
      'error': 'invalid_request',
      'error_description': 'AADSTS900561: secret user information',
    });
    expect(error.message, contains('restart sign-in'));
    expect(error.message, contains('AADSTS900561'));
    expect(error.message, isNot(contains('secret user information')));
  });

  test('unreadable server error retains actionable HTTP guidance', () {
    final service = OneDriveService();
    addTearDown(service.dispose);
    final response = http.Response('<html>failure</html>', 503);
    final error = service.responseError(response, service.decode(response));
    expect(error.message, contains('temporarily unavailable'));
    expect(error.message, contains('HTTP 503'));
  });

  test('network failure becomes a user-facing exception', () async {
    final service = OneDriveService(
      client: MockClient((_) async {
        throw http.ClientException('private network details');
      }),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.startSignIn(OneDriveService.defaultClientId),
      throwsA(
        isA<OneDriveException>().having(
          (e) => e.message,
          'message',
          contains('Check your internet connection'),
        ),
      ),
    );
  });

  test('sign-in recovers from token network failure and uploads', () async {
    var tokenAttempts = 0;
    var foregroundChecks = 0;
    final requests = <http.Request>[];
    final service = OneDriveService(
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/devicecode')) {
          expect(request.url.path, '/consumers/oauth2/v2.0/devicecode');
          expect(
            request.bodyFields['client_id'],
            OneDriveService.defaultClientId,
          );
          return http.Response(
            jsonEncode({
              'user_code': 'code',
              'device_code': 'device',
              'verification_uri': 'https://microsoft.com/devicelogin',
              'expires_in': 600,
              'interval': 1,
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/token')) {
          if (++tokenAttempts == 1) {
            throw http.ClientException('temporary interruption');
          }
          expect(request.url.path, '/consumers/oauth2/v2.0/token');
          expect(
            request.bodyFields['client_id'],
            OneDriveService.defaultClientId,
          );
          return http.Response(
            jsonEncode({'access_token': 'test', 'expires_in': 3600}),
            200,
          );
        }
        if (request.method == 'GET') {
          expect(request.url.path, contains('/shares/u!'));
          return http.Response(
            jsonEncode({
              'id': 'folder',
              'folder': {},
              'parentReference': {'driveId': 'drive'},
            }),
            200,
          );
        }
        expect(request.method, 'PUT');
        expect(
          request.url.path,
          '/v1.0/drives/drive/items/folder:/stock.xlsx:/content',
        );
        return http.Response(
          jsonEncode({
            'id': 'report',
            'webUrl': 'https://onedrive.live.com/report',
          }),
          201,
        );
      }),
    );
    await service.finishSignIn(
      OneDriveService.defaultClientId,
      await service.startSignIn(OneDriveService.defaultClientId),
      () => false,
      wait: (_) async {},
      beforePoll: () async {
        foregroundChecks++;
      },
    );
    final result = await service.upload(
      'stock.xlsx',
      Uint8List.fromList([1, 2]),
    );
    expect(result.scheme, 'https');
    expect(requests.length, 5);
    expect(foregroundChecks, 2);
    service.dispose();
  });
}
