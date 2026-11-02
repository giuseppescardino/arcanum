import 'package:flutter/material.dart';

import '../app/vault_controller.dart';
import '../src/rust/api/vault.dart';
import '../ui/theme.dart';
import '../ui/unlock_screen.dart';
import '../ui/widgets.dart';
import 'autofill_bridge.dart';
import 'matching.dart';

/// UI shown by Android's AutofillActivity: unlock, then pick a credential.
class AutofillApp extends StatelessWidget {
  const AutofillApp({
    super.key,
    required this.controller,
    required this.bridge,
    required this.request,
  });

  final VaultController controller;
  final AutofillBridge bridge;
  final AutofillRequest request;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => MaterialApp(
        title: 'Arcanum',
        debugShowCheckedModeBanner: false,
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        home: KeyedSubtree(
          key: ValueKey(controller.stage),
          child: switch (controller.stage) {
            VaultStage.setup ||
            VaultStage.emergencyKit => _NoVault(bridge: bridge),
            VaultStage.locked => UnlockScreen(controller: controller),
            VaultStage.unlocked => AutofillPickerScreen(
              controller: controller,
              bridge: bridge,
              request: request,
            ),
          },
        ),
      ),
    );
  }
}

class _NoVault extends StatelessWidget {
  const _NoVault({required this.bridge});

  final AutofillBridge bridge;

  @override
  Widget build(BuildContext context) {
    return NarrowPage(
      children: [
        const Icon(Icons.info_outline, size: 48),
        const SizedBox(height: 16),
        const Text(
          'Non c\'è ancora un vault su questo dispositivo. Apri Password '
          'Manager per crearlo o accedere al tuo account.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: bridge.cancel, child: const Text('Chiudi')),
      ],
    );
  }
}

class AutofillPickerScreen extends StatefulWidget {
  const AutofillPickerScreen({
    super.key,
    required this.controller,
    required this.bridge,
    required this.request,
  });

  final VaultController controller;
  final AutofillBridge bridge;
  final AutofillRequest request;

  @override
  State<AutofillPickerScreen> createState() => _AutofillPickerScreenState();
}

class _AutofillPickerScreenState extends State<AutofillPickerScreen> {
  String _query = '';

  List<VaultItem> get _logins => widget.controller.items
      .where((i) => i.fields.kind == VaultItemKind.login)
      .where((i) {
        final q = _query.trim().toLowerCase();
        if (q.isEmpty) return true;
        final f = i.fields;
        return f.title.toLowerCase().contains(q) ||
            f.username.toLowerCase().contains(q) ||
            f.urls.any((u) => u.toLowerCase().contains(q));
      })
      .toList();

  Future<void> _pick(VaultItem item) async {
    final f = item.fields;
    final domain = widget.request.webDomain;
    // Filling a site the item isn't saved for is allowed but confirmed:
    // that's exactly what a phishing page would ask for.
    if (domain != null && !isSuggested(item, widget.request)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sito diverso'),
          content: Text(
            '"${f.title}" non è salvato per $domain. Compilare comunque? '
            'Fallo solo se sei sicuro che il sito sia autentico.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Compila'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await widget.bridge.fill(username: f.username, password: f.password);
  }

  @override
  Widget build(BuildContext context) {
    final logins = _logins;
    final suggested = logins
        .where((i) => isSuggested(i, widget.request))
        .toList();
    final others = logins.where((i) => !suggested.contains(i)).toList();
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Annulla',
          icon: const Icon(Icons.close),
          onPressed: widget.bridge.cancel,
        ),
        title: const Text('Scegli le credenziali'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Richiesto da: ${widget.request.displayName}',
                  key: const ValueKey('autofill-requester'),
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Cerca',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: logins.isEmpty
          ? const Center(child: Text('Nessuna credenziale trovata.'))
          : ListView(
              children: [
                if (suggested.isNotEmpty) ...[
                  const _Header('Suggeriti'),
                  for (final i in suggested) _tile(i),
                ],
                if (others.isNotEmpty) ...[
                  _Header(suggested.isEmpty ? 'Tutte le credenziali' : 'Altre'),
                  for (final i in others) _tile(i),
                ],
              ],
            ),
    );
  }

  Widget _tile(VaultItem item) {
    final f = item.fields;
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.key)),
      title: Text(f.title.isEmpty ? '(senza titolo)' : f.title),
      subtitle: f.username.isEmpty ? null : Text(f.username),
      onTap: () => _pick(item),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
