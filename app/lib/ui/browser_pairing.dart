import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../browser/bridge_server.dart';
import '../l10n/l10n.dart';

/// Makes the browser bridge reachable from the vault menu; absent on
/// mobile, where the server does not run.
class BridgeScope extends InheritedNotifier<BridgeServer> {
  const BridgeScope({
    super.key,
    required BridgeServer server,
    required super.child,
  }) : super(notifier: server);

  static BridgeServer? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BridgeScope>()?.notifier;
}

/// "Browser collegati": pair the extension, list and revoke browsers.
class BrowserPairingScreen extends StatefulWidget {
  const BrowserPairingScreen({super.key, required this.server});

  final BridgeServer server;

  @override
  State<BrowserPairingScreen> createState() => _BrowserPairingScreenState();
}

class _BrowserPairingScreenState extends State<BrowserPairingScreen> {
  BridgeServer get _server => widget.server;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _server.addListener(_onChange);
  }

  @override
  void dispose() {
    _server.removeListener(_onChange);
    super.dispose();
  }

  // The server notifies from its request handler, outside any frame:
  // open the dialog from the next frame instead.
  void _onChange() {
    if (_server.pending == null || _dialogOpen) return;
    _dialogOpen = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted && _server.pending != null) {
          _showDialog();
        } else {
          _dialogOpen = false;
        }
      })
      ..scheduleFrame();
  }

  Future<void> _showDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PairingDialog(server: _server),
    );
    _dialogOpen = false;
    // Closing the dialog any way other than "Collega" ends the pairing.
    if (_server.pending != null) _server.reject();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.browsersTitle)),
      body: ListenableBuilder(
        listenable: _server,
        builder: (context, _) {
          final browsers = _server.browsers;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_server.error != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(l10n.browsersPortsBusy),
                  ),
                ),
              Text(l10n.browsersIntro),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_link),
                  label: Text(l10n.browsersConnect),
                  onPressed: _server.port == null ? null : _server.openPairing,
                ),
              ),
              if (_server.pairingOpen && _server.pending == null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(l10n.browsersWaiting)),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              if (browsers.isEmpty)
                Text(l10n.browsersNone)
              else
                for (final b in browsers)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.web),
                    title: Text(b.name),
                    subtitle: Text(
                      l10n.browsersConnectedOn(
                        DateFormat.yMd(locale).format(b.created),
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: () => _server.revoke(b.id),
                      child: Text(l10n.browsersRevoke),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _PairingDialog extends StatefulWidget {
  const _PairingDialog({required this.server});

  final BridgeServer server;

  @override
  State<_PairingDialog> createState() => _PairingDialogState();
}

/// The user types the code the browser shows. The app never displays it,
/// so whoever started the pairing can only be approved by someone who can
/// see that browser.
class _PairingDialogState extends State<_PairingDialog> {
  final _code = TextEditingController();
  bool _wrong = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final result = await widget.server.approve(_code.text);
    if (!mounted) return;
    if (result == PairingResult.wrongCode) {
      setState(() => _wrong = true);
      _code.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final server = widget.server;
    return ListenableBuilder(
      listenable: server,
      builder: (context, _) {
        final pending = server.pending;
        if (pending == null) {
          // Expired, approved or rejected: close.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).pop();
          });
          return const SizedBox.shrink();
        }
        return AlertDialog(
          title: Text(l10n.browsersPairTitle(pending.name)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.browsersPairBody),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 7,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  errorText: _wrong ? l10n.browsersWrongCode : null,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: server.reject,
              child: Text(l10n.browsersReject),
            ),
            FilledButton(onPressed: _submit, child: Text(l10n.browsersApprove)),
          ],
        );
      },
    );
  }
}
