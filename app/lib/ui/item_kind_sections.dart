import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/cards.dart';
import '../app/clipboard.dart';
import '../app/wifi_qr.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import 'strength_meter.dart';
import 'widgets.dart';

// ------------------------------------------------------------------ Wi-Fi

/// Editor state of a Wi-Fi item; the password lives in the editor's
/// password controller, shared with logins.
class WifiDraft {
  WifiDraft(WifiFields? f)
    : ssid = TextEditingController(text: f?.ssid),
      security = f?.security ?? WifiSecurityKind.wpa,
      hidden = f?.hidden ?? false;

  final TextEditingController ssid;
  WifiSecurityKind security;
  bool hidden;

  WifiFields toFields() =>
      WifiFields(ssid: ssid.text.trim(), security: security, hidden: hidden);

  void dispose() => ssid.dispose();
}

class WifiSection extends StatefulWidget {
  const WifiSection({super.key, required this.draft, required this.password});

  final WifiDraft draft;
  final TextEditingController password;

  @override
  State<WifiSection> createState() => _WifiSectionState();
}

class _WifiSectionState extends State<WifiSection> {
  WifiDraft get _d => widget.draft;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final needsPassword = _d.security != WifiSecurityKind.none;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const Key('wifiSsid'),
          controller: _d.ssid,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: l10n.wifiSsid),
          validator: (v) =>
              (v ?? '').trim().isEmpty ? l10n.wifiSsidRequired : null,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<WifiSecurityKind>(
          initialValue: _d.security,
          decoration: InputDecoration(labelText: l10n.wifiSecurity),
          items: [
            DropdownMenuItem(
              value: WifiSecurityKind.wpa,
              child: Text(l10n.wifiSecurityWpa),
            ),
            DropdownMenuItem(
              value: WifiSecurityKind.wep,
              child: Text(l10n.wifiSecurityWep),
            ),
            DropdownMenuItem(
              value: WifiSecurityKind.none,
              child: Text(l10n.wifiSecurityNone),
            ),
          ],
          onChanged: (v) => setState(() => _d.security = v ?? _d.security),
        ),
        if (needsPassword) ...[
          const SizedBox(height: 16),
          PasswordField(
            controller: widget.password,
            label: context.l10n.password,
            trailing: IconButton(
              tooltip: l10n.copy,
              icon: const Icon(Icons.copy),
              onPressed: () => copySecret(
                context,
                widget.password.text,
                label: l10n.password,
              ),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: widget.password,
            builder: (_, value, _) => StrengthMeter(password: value.text),
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.wifiHidden),
          value: _d.hidden,
          onChanged: (v) => setState(() => _d.hidden = v),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.qr_code_2),
          label: Text(l10n.wifiShowQr),
          onPressed: () {
            final ssid = _d.ssid.text.trim();
            if (ssid.isEmpty) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(l10n.wifiSsidRequired)));
              return;
            }
            showWifiQr(
              context,
              ssid: ssid,
              security: _d.security,
              password: widget.password.text,
              hidden: _d.hidden,
            );
          },
        ),
      ],
    );
  }
}

/// Full-screen-ish QR code another phone scans with its camera to join.
Future<void> showWifiQr(
  BuildContext context, {
  required String ssid,
  required WifiSecurityKind security,
  required String password,
  bool hidden = false,
}) {
  final payload = wifiQrPayload(
    ssid: ssid,
    security: security,
    password: password,
    hidden: hidden,
  );
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ssid, textAlign: TextAlign.center),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Always dark on white: cameras read it in either theme.
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(
                key: const Key('wifiQr'),
                data: payload,
                size: 256,
                backgroundColor: Colors.white,
                semanticsLabel: ctx.l10n.wifiQrSemantics(ssid),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              ctx.l10n.wifiQrHint,
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.l10n.close),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------------- Card

class CardDraft {
  CardDraft(CardFields? f)
    : holder = TextEditingController(text: f?.holder),
      number = TextEditingController(
        text: f == null ? '' : formatCardNumber(f.number),
      ),
      expiry = TextEditingController(text: f?.expiry),
      cvv = TextEditingController(text: f?.cvv),
      pin = TextEditingController(text: f?.pin);

  final TextEditingController holder;
  final TextEditingController number;
  final TextEditingController expiry;
  final TextEditingController cvv;
  final TextEditingController pin;

  CardFields toFields() => CardFields(
    holder: holder.text.trim(),
    number: cardDigits(number.text),
    expiry: normalizeExpiry(expiry.text),
    cvv: cvv.text.trim(),
    pin: pin.text.trim(),
  );

  void dispose() {
    for (final c in [holder, number, expiry, cvv, pin]) {
      c.dispose();
    }
  }
}

/// Keeps the number grouped as it is printed on the card while typing.
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = cardDigits(newValue.text);
    if (digits.length > 19) return oldValue;
    final digitsBeforeCursor = cardDigits(
      newValue.text.substring(
        0,
        newValue.selection.end.clamp(0, newValue.text.length),
      ),
    ).length;
    final formatted = formatCardNumber(digits);
    var offset = 0;
    for (var seen = 0; offset < formatted.length; offset++) {
      if (seen == digitsBeforeCursor) break;
      if (formatted[offset] != ' ') seen++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// Inserts the slash after the month: `0829` -> `08/29`.
class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Deleting the slash also deletes the digit before it.
    if (oldValue.text.endsWith('/') &&
        newValue.text.length < oldValue.text.length) {
      final t = newValue.text.substring(
        0,
        (newValue.text.length - 1).clamp(0, 5),
      );
      return TextEditingValue(
        text: t,
        selection: TextSelection.collapsed(offset: t.length),
      );
    }
    final d = cardDigits(newValue.text);
    if (d.length > 4) return oldValue;
    final t = d.length >= 2 ? '${d.substring(0, 2)}/${d.substring(2)}' : d;
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}

class CardSection extends StatelessWidget {
  const CardSection({super.key, required this.draft});

  final CardDraft draft;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget copy(TextEditingController c, String label) => IconButton(
      tooltip: l10n.copy,
      icon: const Icon(Icons.copy),
      onPressed: () => copySecret(
        context,
        c == draft.number ? cardDigits(c.text) : c.text,
        label: label,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: draft.holder,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: l10n.cardHolder),
        ),
        const SizedBox(height: 16),
        ValueListenableBuilder(
          valueListenable: draft.number,
          builder: (context, value, _) {
            final brand = cardBrand(value.text);
            final complete =
                cardDigits(value.text).length >= 12 &&
                cardNumberProblem(value.text) == null;
            return TextFormField(
              key: const Key('cardNumber'),
              controller: draft.number,
              keyboardType: TextInputType.number,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [_CardNumberFormatter()],
              textInputAction: TextInputAction.next,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: InputDecoration(
                labelText: l10n.cardNumber,
                prefixIcon: const Icon(Icons.credit_card),
                helperText: brand == CardBrand.unknown
                    ? null
                    : complete
                    ? l10n.cardNumberValid(brand.label)
                    : brand.label,
                suffixIcon: copy(draft.number, l10n.cardNumber),
              ),
              validator: (v) {
                if (cardDigits(v ?? '').isEmpty) return null;
                return switch (cardNumberProblem(v!)) {
                  null => null,
                  CardNumberProblem.tooShort => l10n.cardNumberTooShort,
                  CardNumberProblem.wrongLength => l10n.cardNumberWrongLength(
                    brand == CardBrand.unknown
                        ? l10n.cardBrandUnknown
                        : brand.label,
                  ),
                  CardNumberProblem.checksum => l10n.cardNumberChecksum,
                };
              },
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: draft.expiry,
                builder: (context, value, _) => TextFormField(
                  key: const Key('cardExpiry'),
                  controller: draft.expiry,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_ExpiryFormatter()],
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: InputDecoration(
                    labelText: l10n.cardExpiry,
                    hintText: l10n.cardExpiryHint,
                    // Expired cards can still be stored: a warning only.
                    helperText:
                        cardExpiryProblem(value.text) ==
                            CardExpiryProblem.expired
                        ? l10n.cardExpired
                        : null,
                    helperStyle: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) return null;
                    return parseExpiry(v!) == null
                        ? l10n.cardExpiryInvalid
                        : null;
                  },
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: PasswordField(
                controller: draft.cvv,
                label: l10n.cardCvv,
                trailing: copy(draft.cvv, l10n.cardCvv),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PasswordField(
          controller: draft.pin,
          label: l10n.cardPin,
          trailing: copy(draft.pin, l10n.cardPin),
        ),
      ],
    );
  }
}
