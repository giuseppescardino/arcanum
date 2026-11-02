import '../src/rust/api/vault.dart';
import 'autofill_bridge.dart';

/// Package-name parts that say nothing about the service.
const _genericParts = {
  'com',
  'org',
  'net',
  'android',
  'app',
  'apps',
  'mobile',
  'client',
  'www',
  'google',
  'beta',
  'debug',
  'release',
  'main',
};

String? hostOf(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(
    trimmed.contains('://') ? trimmed : 'https://$trimmed',
  );
  final host = uri?.host.toLowerCase();
  if (host == null || host.isEmpty) return null;
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// Same host, or one is a subdomain of the other on a label boundary
/// (`accounts.example.com` ~ `example.com`, but not `evil-example.com`).
bool hostsMatch(String a, String b) {
  a = a.startsWith('www.') ? a.substring(4) : a;
  b = b.startsWith('www.') ? b.substring(4) : b;
  return a == b || a.endsWith('.$b') || b.endsWith('.$a');
}

/// Whether [item] is a likely match for the requesting site or app. This
/// only orders the list: the user always confirms the choice.
bool isSuggested(VaultItem item, AutofillRequest request) {
  final f = item.fields;
  if (f.kind != VaultItemKind.login) return false;
  final hosts = f.urls.map(hostOf).whereType<String>();

  final domain = request.webDomain;
  if (domain != null && domain.isNotEmpty) {
    final d = domain.toLowerCase();
    return hosts.any((h) => hostsMatch(h, d));
  }

  // Native app: match meaningful package-name parts against the item.
  final parts = request.packageName
      .toLowerCase()
      .split('.')
      .where((p) => p.length >= 4 && !_genericParts.contains(p));
  final title = f.title.toLowerCase();
  return parts.any(
    (p) => title.contains(p) || hosts.any((h) => h.split('.').contains(p)),
  );
}
