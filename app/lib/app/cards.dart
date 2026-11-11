/// Payment card checks: number (Luhn and length per network) and expiry.
library;

enum CardBrand {
  visa('Visa', [13, 16, 19]),
  mastercard('Mastercard', [16]),
  amex('American Express', [15]),
  maestro('Maestro', [12, 13, 14, 15, 16, 17, 18, 19]),
  discover('Discover', [16, 19]),
  dinersClub('Diners Club', [14, 16, 19]),
  jcb('JCB', [16, 17, 18, 19]),
  unionPay('UnionPay', [16, 17, 18, 19]),
  unknown('', [12, 13, 14, 15, 16, 17, 18, 19]);

  const CardBrand(this.label, this.lengths);
  final String label;

  /// Valid lengths of a number of this network.
  final List<int> lengths;
}

/// The digits of [input], spaces and dashes dropped.
String cardDigits(String input) => input.replaceAll(RegExp(r'\D'), '');

bool _inRange(String digits, int length, int from, int to) {
  if (digits.length < length) return false;
  final n = int.parse(digits.substring(0, length));
  return n >= from && n <= to;
}

/// Network of a card number, from its leading digits (IIN ranges).
CardBrand cardBrand(String number) {
  final d = cardDigits(number);
  if (d.isEmpty) return CardBrand.unknown;
  if (d.startsWith('34') || d.startsWith('37')) return CardBrand.amex;
  if (_inRange(d, 2, 51, 55) || _inRange(d, 4, 2221, 2720)) {
    return CardBrand.mastercard;
  }
  if (d.startsWith('6011') ||
      d.startsWith('65') ||
      _inRange(d, 3, 644, 649) ||
      _inRange(d, 6, 622126, 622925)) {
    return CardBrand.discover;
  }
  if (d.startsWith('62')) return CardBrand.unionPay;
  if (_inRange(d, 4, 3528, 3589)) return CardBrand.jcb;
  if (d.startsWith('36') ||
      d.startsWith('38') ||
      d.startsWith('39') ||
      _inRange(d, 3, 300, 305)) {
    return CardBrand.dinersClub;
  }
  if (d.startsWith('50') || _inRange(d, 2, 56, 69)) return CardBrand.maestro;
  if (d.startsWith('4')) return CardBrand.visa;
  return CardBrand.unknown;
}

/// Luhn (mod 10) checksum, which every card network uses.
bool luhnValid(String number) {
  final d = cardDigits(number);
  if (d.isEmpty) return false;
  var sum = 0;
  for (var i = 0; i < d.length; i++) {
    var n = d.codeUnitAt(d.length - 1 - i) - 48;
    if (i.isOdd) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
  }
  return sum % 10 == 0;
}

enum CardNumberProblem { tooShort, wrongLength, checksum }

/// Why [number] is not a valid card number, or null when it is.
CardNumberProblem? cardNumberProblem(String number) {
  final d = cardDigits(number);
  final brand = cardBrand(d);
  if (d.length < 12) return CardNumberProblem.tooShort;
  if (!brand.lengths.contains(d.length)) return CardNumberProblem.wrongLength;
  if (!luhnValid(d)) return CardNumberProblem.checksum;
  return null;
}

/// Groups digits the way they are printed: 4-6-5 for American Express
/// (and 4-6-4 for 14-digit Diners), blocks of four otherwise.
String formatCardNumber(String number) {
  final d = cardDigits(number);
  final List<int> groups = switch ((cardBrand(d), d.length)) {
    (CardBrand.amex, _) => [4, 6, 5],
    (CardBrand.dinersClub, 14) => [4, 6, 4],
    _ => [],
  };
  final out = StringBuffer();
  var i = 0;
  var g = 0;
  while (i < d.length) {
    final size = g < groups.length ? groups[g] : 4;
    if (out.isNotEmpty) out.write(' ');
    out.write(d.substring(i, (i + size).clamp(0, d.length)));
    i += size;
    g++;
  }
  return out.toString();
}

/// `•••• 1234`: enough to recognize the card in a list.
String maskCardNumber(String number) {
  final d = cardDigits(number);
  if (d.length < 4) return d;
  return '•••• ${d.substring(d.length - 4)}';
}

enum CardExpiryProblem { format, expired }

/// Parses `MM/YY` (or `MM/YYYY`); null when malformed.
({int month, int year})? parseExpiry(String input) {
  final m = RegExp(r'^\s*(\d{1,2})\s*/\s*(\d{2}|\d{4})\s*$').firstMatch(input);
  if (m == null) return null;
  final month = int.parse(m.group(1)!);
  var year = int.parse(m.group(2)!);
  if (month < 1 || month > 12) return null;
  if (year < 100) year += 2000;
  return (month: month, year: year);
}

/// Normalizes a valid expiry to `MM/YY`; leaves anything else unchanged.
String normalizeExpiry(String input) {
  final e = parseExpiry(input);
  if (e == null) return input.trim();
  return '${e.month.toString().padLeft(2, '0')}/'
      '${(e.year % 100).toString().padLeft(2, '0')}';
}

/// Why [input] is not a usable expiry, or null. A card is valid through
/// the last day of its expiry month.
CardExpiryProblem? cardExpiryProblem(String input, {DateTime? now}) {
  final e = parseExpiry(input);
  if (e == null) return CardExpiryProblem.format;
  now ??= DateTime.now();
  if (e.year < now.year || (e.year == now.year && e.month < now.month)) {
    return CardExpiryProblem.expired;
  }
  return null;
}
