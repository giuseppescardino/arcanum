import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android only: mirrors the in-app language choice into the system's
/// per-app language (Android 13+), so strings Android renders itself, such
/// as the autofill entry, use the same language as the app.
class AndroidLanguage {
  AndroidLanguage._();

  static const _channel = MethodChannel('pm/platform');

  static Future<void> apply(String? languageCode) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('setAppLanguage', {
        'code': languageCode,
      });
    } on PlatformException {
      // Older Android or unsupported: the system language still applies.
    } on MissingPluginException {
      // Autofill entry point: the channel lives in MainActivity only.
    }
  }
}
