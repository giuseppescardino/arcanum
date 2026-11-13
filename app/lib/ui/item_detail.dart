import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/cards.dart' show formatCardNumber, maskCardNumber;
import '../app/clipboard.dart';
import '../app/expiry.dart';
import '../app/tools.dart';
import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import 'breach_status.dart';
import 'item_editor_screen.dart';
import 'item_kind_sections.dart' show showWifiQr;
import 'markdown_notes.dart';
import 'site_icon.dart';
import 'strength_meter.dart';
import 'totp_view.dart';

const _mask = '••••••••';

/// Read-only view of the item with [itemId], following [controller]. Shows
/// [empty] when the item is not in the vault.
class ItemDetailView extends StatelessWidget {
  const ItemDetailView({
    super.key,
    required this.controller,
    required this.itemId,
    required this.onEdit,
    this.empty,
  });

  final VaultController controller;
  final String itemId;

  /// The one way to change the item; nothing here writes to the vault.
  final void Function(VaultItem item) onEdit;

  /// Shown when [itemId] is not in the vault.
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final item = controller.items.where((i) => i.id == itemId).firstOrNull;
        if (item == null) return empty ?? const SizedBox.shrink();
        return _Body(item: item, onEdit: () => onEdit(item));
      },
    );
  }
}

/// Narrow layout: [ItemDetailView] in a scaffold; pops itself when the
/// item is gone. Its 'Modifica' button pushes [ItemEditorScreen].
class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({
    super.key,
    required this.controller,
    required this.itemId,
  });

  final VaultController controller;
  final String itemId;

  void _edit(BuildContext context, VaultItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemEditorScreen(controller: controller, item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ItemDetailView(
        controller: controller,
        itemId: itemId,
        onEdit: (item) => _edit(context, item),
        empty: const _PopWhenShown(),
      ),
    );
  }
}

/// Closes the route it sits in, once, after the frame that showed it.
class _PopWhenShown extends StatefulWidget {
  const _PopWhenShown();

  @override
  State<_PopWhenShown> createState() => _PopWhenShownState();
}

class _PopWhenShownState extends State<_PopWhenShown> {
  Animation<double>? _above;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  /// Pops once this route is the current one. While a route above (the
  /// editor) is open, waits until it is gone, then tries again.
  void _check() {
    if (!mounted || _popped) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    if (route.isCurrent) {
      _popped = true;
      Navigator.of(context).pop();
    } else {
      _above ??= route.secondaryAnimation?..addStatusListener(_onAboveStatus);
    }
  }

  void _onAboveStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _above?.removeStatusListener(_onAboveStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _Body extends StatelessWidget {
  const _Body({required this.item, required this.onEdit});

  final VaultItem item;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final f = item.fields;
    final id = item.id;
    final isLogin = f.kind == VaultItemKind.login;
    final wifi = f.wifi;
    final card = f.card;
    final totp = f.totp;
    final expiry = expiryOf(f);
    final state = expiryState(f, DateTime.now());
    final dates = MaterialLocalizations.of(context);
    final small = theme.textTheme.bodySmall;
    final muted = theme.colorScheme.onSurfaceVariant;
    final expiryColor = switch (state) {
      ExpiryState.expired => theme.colorScheme.error,
      ExpiryState.soon => theme.colorScheme.tertiary,
      _ => muted,
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                _leadingIcon(f),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.title.isEmpty ? l10n.untitled : f.title,
                        style: theme.textTheme.titleLarge,
                      ),
                      if (f.group.isNotEmpty)
                        Text(f.group, style: small?.copyWith(color: muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(l10n.itemEdit),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isLogin && f.username.isNotEmpty)
              _FieldRow(
                key: ValueKey('$id/username'),
                label: l10n.editorUsernameLabel,
                value: f.username,
                copyLabel: l10n.username,
              ),
            if (isLogin && f.password.isNotEmpty) ...[
              _FieldRow(
                key: ValueKey('$id/password'),
                label: l10n.password,
                value: f.password,
                secret: true,
                copyLabel: l10n.password,
              ),
              StrengthMeter(password: f.password),
              BreachStatus(password: f.password),
              const SizedBox(height: 8),
            ],
            if (isLogin && f.urls.isNotEmpty)
              _FieldRow(
                key: ValueKey('$id/urls'),
                label: l10n.editorWebsites,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final url in f.urls) _Link(url: url)],
                ),
              ),
            if (isLogin && totp != null && tools.isValidTotp(totp))
              _FieldRow(
                key: ValueKey('$id/totp'),
                label: l10n.editorTotpLabel,
                child: TotpView(secret: totp),
              ),
            if (wifi != null) ...[
              _FieldRow(
                key: ValueKey('$id/ssid'),
                label: l10n.wifiSsid,
                value: wifi.ssid,
                copyLabel: l10n.wifiSsid,
              ),
              _FieldRow(
                key: ValueKey('$id/security'),
                label: l10n.wifiSecurity,
                value: switch (wifi.security) {
                  WifiSecurityKind.wpa => l10n.wifiSecurityWpa,
                  WifiSecurityKind.wep => l10n.wifiSecurityWep,
                  WifiSecurityKind.none => l10n.wifiSecurityNone,
                },
              ),
              if (wifi.hidden)
                Text(l10n.wifiHidden, style: small?.copyWith(color: muted)),
              if (wifi.security != WifiSecurityKind.none &&
                  f.password.isNotEmpty)
                _FieldRow(
                  key: ValueKey('$id/password'),
                  label: l10n.password,
                  value: f.password,
                  secret: true,
                  copyLabel: l10n.password,
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(l10n.wifiShowQr),
                  onPressed: () => showWifiQr(
                    context,
                    ssid: wifi.ssid,
                    security: wifi.security,
                    password: f.password,
                    hidden: wifi.hidden,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (card != null) ...[
              if (card.holder.isNotEmpty)
                _FieldRow(
                  key: ValueKey('$id/holder'),
                  label: l10n.cardHolder,
                  value: card.holder,
                ),
              if (card.number.isNotEmpty)
                _FieldRow(
                  key: ValueKey('$id/number'),
                  label: l10n.cardNumber,
                  value: card.number,
                  secret: true,
                  masked: maskCardNumber(card.number),
                  revealed: formatCardNumber(card.number),
                  copyLabel: l10n.cardNumber,
                ),
              if (card.expiry.isNotEmpty)
                _FieldRow(
                  key: ValueKey('$id/expiry'),
                  label: l10n.cardExpiry,
                  value: card.expiry,
                ),
              if (card.cvv.isNotEmpty)
                _FieldRow(
                  key: ValueKey('$id/cvv'),
                  label: l10n.cardCvv,
                  value: card.cvv,
                  secret: true,
                  copyLabel: l10n.cardCvv,
                ),
              if (card.pin.isNotEmpty)
                _FieldRow(
                  key: ValueKey('$id/pin'),
                  label: l10n.cardPin,
                  value: card.pin,
                  secret: true,
                  copyLabel: l10n.cardPin,
                ),
            ],
            if (f.notes.isNotEmpty)
              _FieldRow(
                key: ValueKey('$id/notes'),
                label: l10n.editorNotes,
                child: MarkdownNotesView(text: f.notes),
              ),
            const Divider(height: 32),
            if (expiry != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  state == ExpiryState.expired
                      ? l10n.itemExpiredOn(dates.formatCompactDate(expiry))
                      : l10n.itemExpiresOn(dates.formatCompactDate(expiry)),
                  style: small?.copyWith(color: expiryColor),
                ),
              ),
            Text(
              l10n.itemUpdatedOn(
                dates.formatCompactDate(
                  DateTime.fromMillisecondsSinceEpoch(item.updatedAt),
                ),
              ),
              style: small?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _leadingIcon(ItemFields f) => switch (f.kind) {
    VaultItemKind.login => SiteIcon(
      url: f.urls.firstOrNull,
      fallback: Icons.key,
    ),
    VaultItemKind.wifi => const ItemAvatar(child: Icon(Icons.wifi)),
    VaultItemKind.card => const ItemAvatar(child: Icon(Icons.credit_card)),
    _ => const ItemAvatar(child: Icon(Icons.sticky_note_2_outlined)),
  };
}

/// Caption, value and trailing buttons. A secret value stays masked until
/// revealed; that state lives here, so it resets when the row is rebuilt
/// under another item's key.
class _FieldRow extends StatefulWidget {
  const _FieldRow({
    super.key,
    required this.label,
    this.value,
    this.child,
    this.secret = false,
    this.masked = _mask,
    this.revealed,
    this.copyLabel,
  });

  final String label;

  /// Plain text value; also what copy puts on the clipboard.
  final String? value;

  /// Custom content in place of [value].
  final Widget? child;
  final bool secret;

  /// Text shown while a secret is hidden.
  final String masked;

  /// Text shown once revealed; defaults to [value].
  final String? revealed;

  /// Names the value in the copy confirmation; no copy button without it.
  final String? copyLabel;

  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final value = widget.value ?? '';
    final shown = widget.secret
        ? (_revealed ? widget.revealed ?? value : widget.masked)
        : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                widget.child ??
                    SelectableText(
                      shown,
                      style: widget.secret
                          ? theme.textTheme.bodyLarge?.copyWith(
                              fontFamily: 'monospace',
                            )
                          : theme.textTheme.bodyLarge,
                    ),
              ],
            ),
          ),
          if (widget.secret)
            IconButton(
              tooltip: _revealed ? l10n.hide : l10n.show,
              icon: Icon(_revealed ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _revealed = !_revealed),
            ),
          if (widget.copyLabel != null)
            IconButton(
              tooltip: l10n.copy,
              icon: const Icon(Icons.copy),
              onPressed: () =>
                  copySecret(context, value, label: widget.copyLabel!),
            ),
        ],
      ),
    );
  }
}

/// A website of the item; opens in the system browser.
class _Link extends StatelessWidget {
  const _Link({required this.url});

  final String url;

  static final _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');

  Future<void> _open() async {
    final uri = Uri.tryParse(_scheme.hasMatch(url) ? url : 'https://$url');
    // Only web links: anything else stored in a URL field is not opened.
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: _open,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          url,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
