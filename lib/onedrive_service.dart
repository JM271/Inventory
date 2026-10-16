import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class OneDriveException implements Exception {
  OneDriveException(this.message, {this.retryable = false});
  final bool retryable;
  final String message;
  @override
  String toString() => message;
}

class DeviceSignIn {
  DeviceSignIn(
    this.code,
    this.deviceCode,
    this.url,
    this.expiresAt,
    this.interval,
  );
  final String code, deviceCode;
  final Uri url;
  final DateTime expiresAt;
  final int interval;
}

class OneDriveService {
  OneDriveService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  // Microsoft app registration named Inventory.
  static const defaultClientId = String.fromEnvironment(
    'INVENTORY_MICROSOFT_CLIENT_ID',
    defaultValue: '7398cfd4-950c-4aa3-91ea-2e092163dc78',
  );
  static const defaultFolderLink =
      'https://1drv.ms/f/c/8a6d120a3054eb1d/IgC5bzCnGJGUS6ID3E3ClwdwAeBSZAA-BZnlm8z0YLQ-SpE?e=PdzmUT';
  String folderLink = defaultFolderLink;
  String? _token;
  DateTime? _expiresAt;
  bool get connected =>
      _token != null &&
      _expiresAt!.isAfter(DateTime.now().add(const Duration(seconds: 30)));
  final _authority = 'https://login.microsoftonline.com/consumers/oauth2/v2.0';
  Map<String, dynamic> decode(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      if (response.statusCode >= 400) {
        return {};
      }
      throw OneDriveException(
        'Microsoft returned an unreadable response (${response.statusCode}). Try again.',
      );
    }
  }

  Future<http.Response> request(
    Future<http.Response> Function() send, {
    bool upload = false,
  }) async {
    try {
      return await send().timeout(Duration(seconds: upload ? 60 : 30));
    } on TimeoutException {
      throw OneDriveException(
        upload
            ? 'Upload confirmation timed out. The file may already be in OneDrive. Retry uses the same filename.'
            : 'Microsoft took too long to respond. Check your connection and start sign-in again.',
        retryable: true,
      );
    } on http.ClientException {
      throw OneDriveException(
        upload
            ? 'Connection lost during upload. Check your internet connection. Retry uses the same filename.'
            : 'Microsoft could not be reached. Check your internet connection and try again.',
        retryable: true,
      );
    }
  }

  OneDriveException responseError(
    http.Response response,
    Map<String, dynamic> data,
  ) {
    if (response.statusCode == 401) disconnect();
    final rawCodes = data['error_codes'];
    final codes = <String>{
      if (rawCodes is List)
        ...rawCodes
            .where((c) => RegExp(r'^\d+$').hasMatch('$c'))
            .map((c) => 'AADSTS$c'),
      ...RegExp(r'AADSTS\d+')
          .allMatches(
            data['error_description'] is String
                ? data['error_description'] as String
                : '',
          )
          .map((m) => m.group(0)!),
    };
    final rawError = data['error'];
    final rawCode = rawError is Map ? rawError['code'] : rawError;
    final error =
        rawCode is String &&
            RegExp(r'^[a-zA-Z0-9_.-]{1,100}$').hasMatch(rawCode)
        ? rawCode
        : null;
    final guidance = <String, String>{
      'AADSTS900561': 'Microsoft received the wrong request method. Close the browser error tab, restart sign-in in Inventory and enter the new code at microsoft.com/devicelogin.',
      'AADSTS50020': 'This account cannot access Inventory. Use a personal Microsoft account and check that Inventory supports personal accounts.',
      'AADSTS50194': 'Inventory does not support this account type. In Entra, enable personal Microsoft accounts and set api.requestedAccessTokenVersion to 2 in the manifest.',
      'AADSTS700016': 'Microsoft could not find Inventory for personal accounts. Check the Inventory client ID and enable personal Microsoft accounts in its app registration.',
      'AADSTS530035': 'Microsoft Security Defaults blocked this sign-in. Use a personal Microsoft account for this configuration. Organization sign-in requires an administrator-approved authentication method.',
      'AADSTS7000218': 'In Inventory’s Microsoft app registration, enable Allow public client flows. No client secret is needed.',
      'AADSTS65001': 'Microsoft permission consent is required. Approve delegated Files.ReadWrite or ask your administrator for consent.',
    };
    String? authGuidance;
    for (final code in codes) {
      if (guidance.containsKey(code)) {
        authGuidance = guidance[code];
        break;
      }
    }
    final detail =
        authGuidance ??
        switch (response.statusCode) {
          401 => 'Microsoft sign-in expired. Sign in again before uploading.',
          403 => 'OneDrive denied access. Check that this account has edit access to the shared folder and that Inventory has delegated Files.ReadWrite permission.',
          404 => 'OneDrive could not be found. Open OneDrive in your browser to finish setting it up for this account.',
          409 => 'OneDrive found a file conflict. Check the report in OneDrive before retrying.',
          413 => 'This report is too large for a single upload.',
          429 =>
            'Microsoft is limiting requests. Wait ${int.tryParse(response.headers['retry-after'] ?? '') ?? 60} seconds before trying again.',
          507 => 'OneDrive storage is full. Free some space and try again.',
          >= 500 => 'Microsoft is temporarily unavailable. Try again later.',
          _ => switch (codes.firstOrNull ?? error) {
            'AADSTS50059' => 'Microsoft could not identify the tenant. Verify the Application (client) ID and Directory (tenant) ID.',
            'AADSTS700016' => 'Microsoft could not find Inventory for personal accounts. Verify the Inventory client ID and enable personal Microsoft accounts in its app registration.',
            'AADSTS530035' => 'Microsoft Security Defaults blocked device-code sign-in. Use a personal Microsoft account, as in Bike Dispatch. Organization accounts may require a different sign-in method.',
            'AADSTS7000218' => 'Enable Allow public client flows in the app registration’s Authentication settings. A client secret is not needed.',
            'AADSTS65001' || 'consent_required' => 'Microsoft permission consent is required. Ask your administrator to approve Files.ReadWrite, then sign in again.',
            'authorization_declined' || 'access_denied' =>
              'Microsoft sign-in was declined. Start sign-in again when ready.',
            'expired_token' => 'The sign-in code expired. Start sign-in again.',
            _ => 'Microsoft could not complete the request. Check the application registration settings and try again.',
          },
        };
    return OneDriveException(
      '$detail (${codes.isNotEmpty ? codes.join(', ') : error ?? 'HTTP ${response.statusCode}'})',
    );
  }

  Future<DeviceSignIn> startSignIn(String clientId) async {
    final response = await request(
      () => _client.post(
        Uri.parse('$_authority/devicecode'),
        body: {
          'client_id': clientId,
          'scope': 'https://graph.microsoft.com/Files.ReadWrite',
        },
      ),
    );
    final data = decode(response);
    if (response.statusCode != 200) {
      throw responseError(response, data);
    }
    if (data['verification_uri'] is! String ||
        data['user_code'] is! String ||
        data['device_code'] is! String ||
        data['expires_in'] is! int ||
        (data['expires_in'] as int) <= 0) {
      throw OneDriveException(
        'Microsoft returned incomplete sign-in details. Start sign-in again.',
      );
    }
    final url = Uri.tryParse(data['verification_uri'] as String);
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      throw OneDriveException('Microsoft returned an invalid sign-in address.');
    }
    return DeviceSignIn(
      data['user_code'],
      data['device_code'],
      url,
      DateTime.now().add(Duration(seconds: data['expires_in'] as int)),
      data['interval'] is int && (data['interval'] as int) > 0
          ? data['interval'] as int
          : 5,
    );
  }

  // Tokens stay in memory only; restarting the app requires sign-in again.
  Future<void> finishSignIn(
    String clientId,
    DeviceSignIn signIn,
    bool Function() cancelled, {
    Future<void> Function(Duration)? wait,
    Future<void> Function()? beforePoll,
  }) async {
    var interval = signIn.interval;
    var failures = 0;
    while (DateTime.now().isBefore(signIn.expiresAt)) {
      await (wait ?? Future<void>.delayed)(Duration(seconds: interval));
      if (cancelled()) {
        return;
      }
      await beforePoll?.call();
      if (cancelled()) return;
      if (!DateTime.now().isBefore(signIn.expiresAt)) break;
      final http.Response response;
      try {
        response = await request(
          () => _client.post(
            Uri.parse('$_authority/token'),
            body: {
              'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
              'client_id': clientId,
              'device_code': signIn.deviceCode,
            },
          ),
        );
      } on OneDriveException catch (error) {
        if (cancelled()) return;
        if (!error.retryable || ++failures >= 3) {
          throw OneDriveException(
            'Could not confirm Microsoft sign-in in Inventory. Return to the app and check the connection to login.microsoftonline.com, then start sign-in again.',
          );
        }
        continue;
      }
      if (cancelled()) {
        return;
      }
      failures = 0;
      final data = decode(response);
      if (response.statusCode == 200) {
        if (data['access_token'] is! String ||
            (data['access_token'] as String).isEmpty ||
            data['expires_in'] is! int ||
            (data['expires_in'] as int) <= 0) {
          throw OneDriveException(
            'Microsoft returned incomplete sign-in details. Sign in again.',
          );
        }
        _token = data['access_token'] as String;
        _expiresAt = DateTime.now().add(
          Duration(seconds: data['expires_in'] as int),
        );
        return;
      }
      if (data['error'] == 'authorization_pending') {
        continue;
      }
      if (data['error'] == 'slow_down') {
        interval += 5;
        continue;
      }
      throw responseError(response, data);
    }
    throw OneDriveException('The sign-in code expired. Start sign-in again.');
  }

  Future<Uri> upload(String filename, Uint8List bytes) async {
    if (!connected) {
      throw OneDriveException('Please sign in to Microsoft again.');
    }
    final link = Uri.tryParse(folderLink.trim());
    if (link == null ||
        link.scheme != 'https' ||
        !(link.host == '1drv.ms' ||
            link.host == 'onedrive.live.com' ||
            link.host == 'onedrive.com' ||
            link.host.endsWith('.sharepoint.com'))) {
      throw OneDriveException(
        'Enter a valid HTTPS OneDrive folder sharing link.',
      );
    }
    final shareId =
        'u!${base64Url.encode(utf8.encode(folderLink.trim())).replaceAll('=', '')}';
    final folderResponse = await request(
      () => _client.get(
        Uri.parse('https://graph.microsoft.com/v1.0/shares/$shareId/driveItem'),
        headers: {'Authorization': 'Bearer $_token'},
      ),
    );
    final folder = decode(folderResponse);
    if (folderResponse.statusCode != 200) {
      throw responseError(folderResponse, folder);
    }
    final parent = folder['parentReference'];
    final driveId = parent is Map ? parent['driveId'] : null;
    final folderId = folder['id'];
    if (folder['folder'] == null || driveId is! String || folderId is! String) {
      throw OneDriveException(
        'The sharing link must point to an accessible OneDrive folder.',
      );
    }
    final response = await request(
      () => _client.put(
        Uri.parse(
          'https://graph.microsoft.com/v1.0/drives/${Uri.encodeComponent(driveId)}/items/${Uri.encodeComponent(folderId)}:/${Uri.encodeComponent(filename)}:/content',
        ),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        },
        body: bytes,
      ),
      upload: true,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      if (response.statusCode == 401) {
        _token = null;
      }
      Map<String, dynamic> data;
      try {
        data = decode(response);
      } on OneDriveException {
        data = {};
      }
      throw responseError(response, data);
    }
    final data = decode(response);
    final url = Uri.tryParse(
      data['webUrl'] is String ? data['webUrl'] as String : '',
    );
    if (data['id'] == null || url == null || url.scheme != 'https') {
      throw OneDriveException(
        'OneDrive did not return a file confirmation. Check OneDrive before retrying.',
      );
    }
    return url;
  }

  void disconnect() {
    _token = null;
    _expiresAt = null;
  }

  void dispose() {
    disconnect();
    _client.close();
  }
}
