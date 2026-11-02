import 'package:flutter/material.dart';

import '../app/messages.dart';
import '../app/vault_controller.dart';
import 'widgets.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key, required this.controller});

  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Sincronizzazione')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: controller.linked
                  ? _LinkedView(controller: controller)
                  : _EnableSyncForm(controller: controller),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkedView extends StatelessWidget {
  const _LinkedView({required this.controller});

  final VaultController controller;

  Future<void> _disconnect(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnettere questo dispositivo?'),
        content: const Text(
          'Il vault resta su questo dispositivo ma smette di sincronizzarsi. '
          'I dati sul server e sugli altri dispositivi non vengono toccati.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnetti'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await controller.disableSync();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failureMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final info = controller.syncInfo;
    final summary = controller.lastSummary;
    final last = controller.lastSync;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ErrorBanner(controller.syncError),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_done_outlined),
                    const SizedBox(width: 8),
                    Text('Sincronizzazione attiva', style: text.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                if (info != null) ...[
                  Text('Account: ${info.email}'),
                  Text('Server: ${info.serverUrl}'),
                ],
                const SizedBox(height: 8),
                Text(
                  last == null
                      ? 'Non ancora sincronizzato in questa sessione.'
                      : 'Ultima sincronizzazione: ${_time(last)}'
                            '${summary == null ? '' : ' (${summary.pulled} ricevuti, ${summary.pushed} inviati'
                                      '${summary.conflicts > 0 ? ', ${summary.conflicts} conflitti' : ''})'}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (controller.sessionExpired)
          FilledButton.icon(
            icon: const Icon(Icons.login),
            label: const Text('Riconnetti'),
            onPressed: () => showReconnectDialog(context, controller),
          )
        else
          FilledButton.icon(
            icon: controller.syncing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: const Text('Sincronizza ora'),
            onPressed: controller.syncing ? null : controller.syncNow,
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _disconnect(context),
          child: const Text('Disconnetti questo dispositivo'),
        ),
        const SizedBox(height: 24),
        Text(
          'I dati vengono cifrati su questo dispositivo prima dell\'invio: '
          'il server conserva solo dati illeggibili e non conosce né la '
          'master password né la Secret Key.',
          style: text.bodySmall,
        ),
      ],
    );
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _EnableSyncForm extends StatefulWidget {
  const _EnableSyncForm({required this.controller});

  final VaultController controller;

  @override
  State<_EnableSyncForm> createState() => _EnableSyncFormState();
}

class _EnableSyncFormState extends State<_EnableSyncForm> {
  final _formKey = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_server, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.enableSync(
        serverUrl: _server.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      );
    } catch (e) {
      if (mounted) setState(() => _error = failureMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.cloud_sync_outlined, size: 56),
          const SizedBox(height: 16),
          Text(
            'Sincronizza tra i tuoi dispositivi',
            style: text.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Crea un account sul tuo server di sincronizzazione. Tutto viene '
            'cifrato qui prima di partire: il server vede solo dati '
            'illeggibili. Sugli altri dispositivi scegli "Ho già un account".',
            style: text.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ErrorBanner(_error),
          ServerUrlField(controller: _server, autofocus: true),
          const SizedBox(height: 16),
          EmailField(controller: _email),
          const SizedBox(height: 16),
          PasswordField(
            controller: _password,
            label: 'Master password (per conferma)',
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            validator: (v) =>
                (v ?? '').isEmpty ? 'Inserisci la master password' : null,
          ),
          const SizedBox(height: 24),
          BusyButton(
            busy: _busy,
            label: 'Attiva sincronizzazione',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

/// Asks for the account's current master password and reconnects.
Future<void> showReconnectDialog(
  BuildContext context,
  VaultController controller,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ReconnectDialog(controller: controller),
  );
}

class _ReconnectDialog extends StatefulWidget {
  const _ReconnectDialog({required this.controller});

  final VaultController controller;

  @override
  State<_ReconnectDialog> createState() => _ReconnectDialogState();
}

class _ReconnectDialogState extends State<_ReconnectDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.reconnect(_password.text);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = failureMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Riconnetti questo dispositivo'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ErrorBanner(_error),
            const Text(
              'Inserisci la master password attuale dell\'account. Se l\'hai '
              'cambiata su un altro dispositivo, usa quella nuova: da ora '
              'varrà anche qui.',
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _password,
              label: 'Master password',
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Riconnetti'),
        ),
      ],
    );
  }
}
