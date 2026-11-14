import '../src/rust/api/vault.dart';

/// An item is "soon" when its last valid day is today or within this window.
const expirySoonWindow = Duration(days: 30);

enum ExpiryState { none, ok, soon, expired }

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _cardExpiry = RegExp(r'^(\d{2})/(\d{2})$');

/// Last valid day (local midnight), from `expiresOn` or, for cards, from
/// `card.expiry` (`MM/YY` → last day of that month in 20YY). Null when
/// unset or unparseable.
DateTime? expiryOf(ItemFields fields) {
  if (fields.kind == VaultItemKind.card) {
    final m = _cardExpiry.firstMatch(fields.card?.expiry ?? '');
    if (m == null) return null;
    final month = int.parse(m[1]!);
    if (month < 1 || month > 12) return null;
    // Day 0 of the next month is the last day of this one.
    return DateTime(2000 + int.parse(m[2]!), month + 1, 0);
  }
  return parseExpiry(fields.expiresOn);
}

/// Strict `YYYY-MM-DD` → local midnight; null for anything else, including
/// dates that do not exist (`2026-02-30`).
DateTime? parseExpiry(String? text) {
  if (text == null || !_isoDate.hasMatch(text)) return null;
  final y = int.parse(text.substring(0, 4));
  final m = int.parse(text.substring(5, 7));
  final d = int.parse(text.substring(8, 10));
  final day = DateTime(y, m, d);
  return day.year == y && day.month == m && day.day == d ? day : null;
}

ExpiryState expiryState(ItemFields fields, DateTime now) {
  final day = expiryOf(fields);
  if (day == null) return ExpiryState.none;
  final today = DateTime(now.year, now.month, now.day);
  if (day.isBefore(today)) return ExpiryState.expired;
  final lastSoon = DateTime(
    today.year,
    today.month,
    today.day + expirySoonWindow.inDays,
  );
  return day.isAfter(lastSoon) ? ExpiryState.ok : ExpiryState.soon;
}

/// `YYYY-MM-DD`.
String formatExpiry(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
