import 'package:flutter/material.dart';

import '../app/messages.dart';
import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import 'widgets.dart';

Future<void> showChangePasswordDialog(
  BuildContext context,
  VaultController controller,
) => showDialog<void>(
  context: context,
  builder: (_) => _ChangePasswordDialog(controller: controller),
);

/// Confirms, then drops the Secret Key stored on this device and locks.
Future<void> forgetSecretKeyOnDevice(
  BuildContext context,
  VaultController controller,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.l10n.vaultForgetSecretKeyTitle),
      content: Text(context.l10n.vaultForgetSecretKeyBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(context.l10n.vaultRemove),
        ),
      ],
    ),
  );
  if (ok == true) {
    await controller.forgetSecretKey();
    controller.lock();
  }
}

Future<bool> _confirmSignOut(BuildContext context, String body) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.l10n.vaultSignOutTitle),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(context.l10n.vaultSignOutConfirm),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Confirms, pushes pending changes when synced, then removes the vault
/// from this device.
Future<void> signOutOfDevice(
  BuildContext context,
  VaultController controller,
) async {
  final l10n = context.l10n;
  final linked = controller.linked;
  if (!await _confirmSignOut(
    context,
    linked ? l10n.vaultSignOutBodySynced : l10n.vaultSignOutBodyLocal,
  )) {
    return;
  }
  if (linked) {
    // Push pending changes first, so nothing is lost with the vault.
    await controller.syncNow();
    if (!context.mounted) return;
    if (controller.syncError != null &&
        !await _confirmSignOut(context, l10n.vaultSignOutSyncFailed)) {
      return;
    }
  }
  try {
    await controller.signOut();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failureMessage(e))));
    }
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.controller});

  final VaultController controller;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.changePassword(_current.text, _next.text);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.vaultMasterPasswordChanged)),
      );
    } catch (e) {
      if (mounted) setState(() => _error = failureMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.vaultChangeMasterPassword),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ErrorBanner(_error),
              PasswordField(
                controller: _current,
                label: context.l10n.vaultCurrentPassword,
                autofocus: true,
                validator: (v) =>
                    (v ?? '').isEmpty ? context.l10n.vaultRequired : null,
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _next,
                label: context.l10n.vaultNewPassword,
                validator: (v) => (v ?? '').length < 10
                    ? context.l10n.vaultMinLength(10)
                    : null,
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _confirm,
                label: context.l10n.vaultRepeatNewPassword,
                onSubmitted: (_) => _submit(),
                validator: (v) =>
                    v != _next.text ? context.l10n.passwordsDontMatch : null,
              ),
            ],
          ),
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
              : Text(context.l10n.vaultChange),
        ),
      ],
    );
  }
}
