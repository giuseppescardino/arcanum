/// Wi-Fi network QR codes: the `WIFI:` format that the iOS and Android
/// cameras recognize and offer to join.
library;

import '../src/rust/api/vault.dart';

/// Escapes the characters that are syntax in the `WIFI:` format.
String _escape(String s) =>
    s.replaceAllMapped(RegExp(r'[\\;,:"]'), (m) => '\\${m.group(0)}');

/// Payload for a network named [ssid]. With [WifiSecurityKind.none] the
/// password is left out.
String wifiQrPayload({
  required String ssid,
  required WifiSecurityKind security,
  required String password,
  bool hidden = false,
}) {
  final type = switch (security) {
    WifiSecurityKind.wpa => 'WPA',
    WifiSecurityKind.wep => 'WEP',
    WifiSecurityKind.none => 'nopass',
  };
  final b = StringBuffer('WIFI:T:$type;S:${_escape(ssid)};');
  if (security != WifiSecurityKind.none) {
    b.write('P:${_escape(password)};');
  }
  if (hidden) b.write('H:true;');
  b.write(';');
  return b.toString();
}
