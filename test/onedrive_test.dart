import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventory/onedrive_service.dart';

void main() {
  test('personal sign-in uploads into the shared folder', () async {
    final requests = <http.Request>[];
    final service = OneDriveService(
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/token')) {
          expect(request.url.path, contains('/consumers/'));
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
      DeviceSignIn(
        'code',
        'device',
        Uri.parse('https://microsoft.com/link'),
        DateTime.now().add(const Duration(minutes: 5)),
        1,
      ),
      () => false,
      wait: (_) async {},
    );
    final result = await service.upload(
      'stock.xlsx',
      Uint8List.fromList([1, 2]),
    );
    expect(result.scheme, 'https');
    expect(requests.length, 3);
    service.dispose();
  });
}
