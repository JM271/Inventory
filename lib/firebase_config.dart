import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Public app identifiers, supplied separately for web/Android/iOS.
/// Replace with FlutterFire-generated options once apps are registered.
class InventoryFirebaseConfig {
  static const projectId = 'inventory-molenstraat';
  static const _apiKeyOverride = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appIdOverride = String.fromEnvironment('FIREBASE_APP_ID');
  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static String get apiKey => _apiKeyOverride.isNotEmpty
      ? _apiKeyOverride
      : _android
      ? 'AIzaSyDOE6hBSQf9lskBUdVy814bNfA6v1JinNg'
      : 'AIzaSyDMeZr_ehiP_q4RJYrLz80DO8JHMhIG_es';
  static String get appId => _appIdOverride.isNotEmpty
      ? _appIdOverride
      : kIsWeb
      ? '1:39036121879:web:be7a88f621967c38cdfd52'
      : _android
      ? '1:39036121879:android:f547da1e6d2d6537cdfd52'
      : '';
  static const senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '39036121879',
  );
  static bool get configured =>
      apiKey.isNotEmpty && appId.isNotEmpty && senderId.isNotEmpty;
  static FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
    authDomain: kIsWeb ? '$projectId.firebaseapp.com' : null,
    iosBundleId: 'ch.jonas.inventory',
  );
}
