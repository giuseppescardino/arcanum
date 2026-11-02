import 'package:flutter/services.dart';

/// Who is asking to be filled (from the Android autofill request).
class AutofillRequest {
  const AutofillRequest({
    required this.packageName,
    this.webDomain,
    this.appLabel,
    this.hasUsername = true,
    this.hasPassword = true,
  });

  final String packageName;

  /// Set when the form is a web page in a browser.
  final String? webDomain;
  final String? appLabel;
  final bool hasUsername;
  final bool hasPassword;

  /// What to show the user as the requester.
  String get displayName => webDomain ?? appLabel ?? packageName;
}

/// Talks to `AutofillActivity` on Android.
abstract class AutofillBridge {
  Future<AutofillRequest> request();
  Future<void> fill({required String username, required String password});
  Future<void> cancel();
}

class ChannelAutofillBridge implements AutofillBridge {
  static const _channel = MethodChannel('pm/autofill');

  @override
  Future<AutofillRequest> request() async {
    final map = await _channel.invokeMapMethod<String, Object?>('request');
    return AutofillRequest(
      packageName: map?['packageName'] as String? ?? '',
      webDomain: map?['webDomain'] as String?,
      appLabel: map?['appLabel'] as String?,
      hasUsername: map?['hasUsername'] as bool? ?? true,
      hasPassword: map?['hasPassword'] as bool? ?? true,
    );
  }

  @override
  Future<void> fill({required String username, required String password}) =>
      _channel.invokeMethod('fill', {
        'username': username,
        'password': password,
      });

  @override
  Future<void> cancel() => _channel.invokeMethod('cancel');
}
