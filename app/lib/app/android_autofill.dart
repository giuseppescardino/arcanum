import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android only: whether an autofill service is set, and a shortcut to the
/// system screen where the user selects this app.
class AndroidAutofill {
  AndroidAutofill._();

  static const _channel = MethodChannel('pm/platform');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> isEnabled() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isAutofillEnabled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> openSettings() =>
      _channel.invokeMethod<void>('openAutofillSettings');
}
