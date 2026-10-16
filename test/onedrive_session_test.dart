import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inventory/report_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventory/onedrive_service.dart';

const storage = FlutterSecureStorage();
const clientId = OneDriveService.defaultClientId;
http.Response token(String access, String refresh) => http.Response(
  jsonEncode({
    'access_token': access,
    'refresh_token': refresh,
    'expires_in': 3600,
  }),
  200,
);
http.Response folder() => http.Response(
  jsonEncode({
    'id': 'folder',
    'folder': {},
    'parentReference': {'driveId': 'drive'},
  }),
  200,
);
http.Response uploaded() => http.Response(
  jsonEncode({'id': 'report', 'webUrl': 'https://onedrive.live.com/report'}),
  201,
);
Future<void> signIn(OneDriveService service) => service.finishSignIn(
  clientId,
  DeviceSignIn(
    'code',
    'device',
    Uri.parse('https://microsoft.com/devicelogin'),
    DateTime.now().add(const Duration(minutes: 5)),
    1,
  ),
  () => false,
  wait: (_) async {},
);
Future<void> seedSession() => storage.write(
  key: OneDriveService.sessionKey,
  value: jsonEncode({'clientId': clientId, 'refreshToken': 'saved-refresh'}),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'closing and reopening retains sign-in and rotates refresh tokens',
    () async {
      final first = OneDriveService(
        client: MockClient((_) async => token('access-one', 'refresh-one')),
      );
      await signIn(first);
      first.dispose();
      final saved = await storage.read(key: OneDriveService.sessionKey);
      expect(saved, contains('refresh-one'));
      expect(saved, isNot(contains('access-one')));
      var refreshes = 0;
      final second = OneDriveService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/token')) {
            refreshes++;
            expect(request.bodyFields['grant_type'], 'refresh_token');
            expect(request.bodyFields['refresh_token'], 'refresh-one');
            return token('access-two', 'refresh-two');
          }
          expect(request.headers['Authorization'], 'Bearer access-two');
          return request.method == 'GET' ? folder() : uploaded();
        }),
      );
      addTearDown(second.dispose);
      await second.restoreSession(clientId);
      expect(second.connected, isTrue);
      await second.upload('one.xlsx', Uint8List(1));
      await second.upload('two.xlsx', Uint8List(1));
      expect(refreshes, 1);
      expect(
        await storage.read(key: OneDriveService.sessionKey),
        contains('refresh-two'),
      );
      await second.disconnect();
      expect(second.connected, isFalse);
      expect(await storage.read(key: OneDriveService.sessionKey), isNull);
    },
  );

  test('a rejected access token is refreshed and retried once', () async {
    await seedSession();
    var refreshes = 0, gets = 0;
    final service = OneDriveService(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          refreshes++;
          return token('access-$refreshes', 'refresh-$refreshes');
        }
        if (request.method == 'GET' && ++gets == 1) {
          return http.Response('{}', 401);
        }
        expect(request.headers['Authorization'], 'Bearer access-2');
        return request.method == 'GET' ? folder() : uploaded();
      }),
    );
    addTearDown(service.dispose);
    await service.restoreSession(clientId);
    await service.upload('report.xlsx', Uint8List(1));
    expect(refreshes, 2);
    expect(gets, 2);
  });

  test('temporary refresh failure keeps saved sign-in for retry', () async {
    await seedSession();
    var attempts = 0;
    final service = OneDriveService(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          if (++attempts == 1) throw http.ClientException('offline');
          return token('access', 'rotated');
        }
        return request.method == 'GET' ? folder() : uploaded();
      }),
    );
    addTearDown(service.dispose);
    await service.restoreSession(clientId);
    await expectLater(
      service.upload('report.xlsx', Uint8List(1)),
      throwsA(isA<OneDriveException>()),
    );
    expect(service.connected, isTrue);
    expect(
      await storage.read(key: OneDriveService.sessionKey),
      contains('saved-refresh'),
    );
    await service.upload('report.xlsx', Uint8List(1));
    expect(attempts, 2);
  });

  test(
    'revoked refresh token requires sign-in and removes saved session',
    () async {
      await seedSession();
      final service = OneDriveService(
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'error': 'invalid_grant'}), 400),
        ),
      );
      addTearDown(service.dispose);
      await service.restoreSession(clientId);
      await expectLater(
        service.upload('report.xlsx', Uint8List(1)),
        throwsA(
          isA<OneDriveException>().having(
            (e) => e.message,
            'message',
            contains('erneute Anmeldung'),
          ),
        ),
      );
      expect(service.connected, isFalse);
      expect(await storage.read(key: OneDriveService.sessionKey), isNull);
    },
  );

  test(
    'saved sign-in cannot be reused by a different app registration',
    () async {
      await seedSession();
      final service = OneDriveService(
        client: MockClient(
          (_) async => throw StateError('No request expected'),
        ),
      );
      addTearDown(service.dispose);
      await service.restoreSession('different-client');
      expect(service.connected, isFalse);
      expect(await storage.read(key: OneDriveService.sessionKey), isNull);
    },
  );
  test('expiring access token is renewed before uploading', () async {
    var refreshes = 0;
    final service = OneDriveService(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          if (request.bodyFields['grant_type'] != 'refresh_token') {
            return http.Response(
              jsonEncode({
                'access_token': 'old',
                'refresh_token': 'refresh',
                'expires_in': 1,
              }),
              200,
            );
          }
          refreshes++;
          return token('renewed', 'rotated');
        }
        expect(request.headers['Authorization'], 'Bearer renewed');
        return request.method == 'GET' ? folder() : uploaded();
      }),
    );
    addTearDown(service.dispose);
    await signIn(service);
    await service.upload('report.xlsx', Uint8List(1));
    expect(refreshes, 1);
  });

  testWidgets(
    'reopened dialog stays connected and sign-out removes saved session',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await seedSession();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ReportDialog(parts: [])),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Upload Excel report'), findsOneWidget);
      expect(find.text('Sign in to Microsoft'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ReportDialog(parts: [])),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Upload Excel report'), findsOneWidget);
      await tester.ensureVisible(find.text('Abmelden / Konto wechseln'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abmelden / Konto wechseln'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to Microsoft'), findsOneWidget);
      expect(await storage.read(key: OneDriveService.sessionKey), isNull);
    },
  );
}
