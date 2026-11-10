import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../autofill/matching.dart';

/// Downloads the icon of [host]; null when there is none.
typedef FaviconFetcher = Future<Uint8List?> Function(String host);

/// Site icons shown next to logins.
///
/// Each icon is requested from the site itself (`https://host/favicon.ico`),
/// never from a third-party service, so nobody else learns which sites are
/// in the vault. Icons are kept in memory only and dropped when the vault
/// locks: a cache on disk would reveal those sites to anyone who can read
/// the disk, which the encrypted vault does not.
class FaviconCache extends ChangeNotifier {
  FaviconCache({FaviconFetcher? fetch, this.prefsPath, this.enabled = true})
    : _fetch = fetch ?? fetchFavicon;

  /// Never downloads anything (default in tests).
  FaviconCache.disabled() : this(enabled: false);

  final FaviconFetcher _fetch;

  /// File whose presence means the user turned site icons off.
  final String? prefsPath;

  /// Changed through [setEnabled].
  bool enabled;
  final Map<String, Future<Uint8List?>> _icons = {};

  Future<void> load() async {
    final path = prefsPath;
    if (path == null) return;
    enabled = !await File(path).exists();
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (value == enabled) return;
    enabled = value;
    if (!value) _icons.clear();
    notifyListeners();
    final path = prefsPath;
    if (path == null) return;
    final file = File(path);
    if (value) {
      if (await file.exists()) await file.delete();
    } else {
      await file.writeAsString('off');
    }
  }

  /// Icon for the site of [url]; null when icons are off, the URL has no
  /// public host name, or the site has no usable icon.
  Future<Uint8List?> iconFor(String url) {
    final host = enabled ? faviconHost(url) : null;
    if (host == null) return Future.value();
    return _icons[host] ??= _fetch(host)
        .then<Uint8List?>((icon) => icon, onError: (Object _) => null);
  }

  /// Forgets every icon (the vault locked).
  void clear() => _icons.clear();
}

final _hostName = RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$');
final _ipAddress = RegExp(r'^[0-9.]+$');

/// Host to ask for the icon of [url]; null for IP addresses, single-label
/// names (`localhost`, intranet hosts) and anything that isn't a host name.
String? faviconHost(String url) {
  final host = hostOf(url);
  if (host == null || !_hostName.hasMatch(host) || _ipAddress.hasMatch(host)) {
    return null;
  }
  return host;
}

const _maxIconBytes = 256 * 1024;
const _maxRedirects = 3;

/// GETs `https://host/favicon.ico`. Only HTTPS, only redirects that stay
/// on the same site, a size cap, and the body must look like an image.
Future<Uint8List?> fetchFavicon(String host) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..userAgent = 'Arcanum-password-manager';
  try {
    var uri = Uri.https(host, '/favicon.ico');
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) return null;
        final next = uri.resolve(location);
        if (next.scheme != 'https' || !hostsMatch(next.host, host)) return null;
        uri = next;
        continue;
      }
      if (response.statusCode != HttpStatus.ok ||
          response.contentLength > _maxIconBytes) {
        await response.drain<void>();
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        bytes.add(chunk);
        if (bytes.length > _maxIconBytes) return null;
      }
      final icon = bytes.takeBytes();
      return looksLikeImage(icon) ? icon : null;
    }
    return null;
  } on Exception {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// ICO, PNG, JPEG, GIF, BMP or WebP by magic number. Keeps error pages
/// served with status 200 (and formats Flutter can't decode) out.
bool looksLikeImage(List<int> b) {
  bool starts(List<int> magic) {
    if (b.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (b[i] != magic[i]) return false;
    }
    return true;
  }

  return starts(const [0x00, 0x00, 0x01, 0x00]) || // ICO
      starts(const [0x89, 0x50, 0x4e, 0x47]) || // PNG
      starts(const [0xff, 0xd8, 0xff]) || // JPEG
      starts(const [0x47, 0x49, 0x46, 0x38]) || // GIF
      starts(const [0x42, 0x4d]) || // BMP
      (starts(const [0x52, 0x49, 0x46, 0x46]) && b.length > 12 && b[8] == 0x57);
}

/// Makes the [FaviconCache] reachable from every route.
class FaviconScope extends InheritedNotifier<FaviconCache> {
  const FaviconScope({
    super.key,
    required FaviconCache cache,
    required super.child,
  }) : super(notifier: cache);

  static FaviconCache? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FaviconScope>()?.notifier;
}
