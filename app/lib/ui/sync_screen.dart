import 'package:flutter/material.dart';

import '../app/messages.dart';
import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import 'widgets.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key, required this.controller});

  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.syncTitle)),
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
        title: Text(ctx.l10n.syncDisconnectTitle),
        content: Text(ctx.l10n.syncDisconnectBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.syncDisconnect),
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
    final l10n = context.l10n;

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
                    Text(l10n.syncActive, style: text.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                if (info != null) Text(l10n.syncServer(info.serverUrl)),
                const SizedBox(height: 8),
                Text(
                  last == null
                      ? l10n.syncNotYetSynced
                      : summary == null
                      ? l10n.syncLastSync(_time(last))
                      : summary.conflicts > 0
                      ? l10n.syncLastSyncSummaryConflicts(
                          _time(last),
                          summary.pulled,
                          summary.pushed,
                          summary.conflicts,
                        )
                      : l10n.syncLastSyncSummary(
                          _time(last),
                          summary.pulled,
                          summary.pushed,
                        ),
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
            label: Text(l10n.reconnect),
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
            label: Text(l10n.syncNow),
            onPressed: controller.syncing ? null : controller.syncNow,
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _disconnect(context),
          child: Text(l10n.syncDisconnectDevice),
        ),
        const SizedBox(height: 24),
        Text(l10n.syncEncryptionNote, style: text.bodySmall),
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
  final _invite = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_server, _invite, _password]) {
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
        password: _password.text,
        invite: _invite.text.trim(),
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
            context.l10n.syncEnableTitle,
            style: text.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.syncEnableBody,
            style: text.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ErrorBanner(_error),
          ServerUrlField(controller: _server, autofocus: true),
          const SizedBox(height: 16),
          InviteCodeField(controller: _invite),
          const SizedBox(height: 16),
          PasswordField(
            controller: _password,
            label: context.l10n.syncConfirmMasterPassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            validator: (v) => (v ?? '').isEmpty
                ? context.l10n.commonEnterMasterPassword
                : null,
          ),
          const SizedBox(height: 24),
          BusyButton(
            busy: _busy,
            label: context.l10n.syncEnable,
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
      title: Text(context.l10n.syncReconnectTitle),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ErrorBanner(_error),
            Text(context.l10n.syncReconnectBody),
            const SizedBox(height: 16),
            PasswordField(
              controller: _password,
              label: context.l10n.masterPassword,
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.l10n.reconnect),
        ),
      ],
    );
  }
}
