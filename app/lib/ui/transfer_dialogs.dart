import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/file_dialogs.dart';
import '../app/messages.dart';
import '../app/transfer.dart';
import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import 'widgets.dart';

void _notify(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

// ------------------------------------------------------------------ import

/// Picks a file, shows what it holds and, once confirmed, adds the items
/// the vault doesn't have yet.
Future<void> importFromFile(
  BuildContext context,
  VaultController controller,
) async {
  final Uint8List? bytes;
  try {
    bytes = await controller.keepUnlocked(fileDialogs.pickFile);
  } catch (e) {
    if (context.mounted) _notify(context, failureMessage(e));
    return;
  }
  if (bytes == null || !context.mounted) return;

  ImportData? data;
  try {
    data = await transfer.parse(bytes);
  } on VaultFailure catch (e) {
    if (!context.mounted) return;
    if (e.code != VaultFailureCode.backupPasswordRequired) {
      _notify(context, failureMessage(e));
      return;
    }
    data = await showDialog<ImportData>(
      context: context,
      builder: (_) => _BackupPasswordDialog(bytes: bytes!),
    );
  }
  if (data == null || !context.mounted) return;

  final fresh = controller.newItemsAmong(data.items);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _ImportPreviewDialog(
      format: data!.format,
      fresh: fresh.length,
      duplicates: data.items.length - fresh.length,
      skipped: data.skipped,
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    final added = await controller.importItems(fresh);
    if (context.mounted) _notify(context, context.l10n.importDone(added));
  } catch (e) {
    if (context.mounted) _notify(context, failureMessage(e));
  }
}

String _formatName(BuildContext context, ImportFormat format) =>
    switch (format) {
      ImportFormat.arcanumBackup => context.l10n.importFormatBackup,
      ImportFormat.csv => 'CSV',
      ImportFormat.bitwarden => 'Bitwarden',
      ImportFormat.onePassword => '1Password',
      ImportFormat.keePass => 'KeePass',
    };

class _ImportPreviewDialog extends StatelessWidget {
  const _ImportPreviewDialog({
    required this.format,
    required this.fresh,
    required this.duplicates,
    required this.skipped,
  });

  final ImportFormat format;
  final int fresh;
  final int duplicates;
  final int skipped;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.importTitle),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.importFormat(_formatName(context, format))),
            const SizedBox(height: 12),
            Text(fresh == 0 ? l10n.importNothing : l10n.importNew(fresh)),
            if (duplicates > 0) Text(l10n.importDuplicates(duplicates)),
            if (skipped > 0) Text(l10n.importSkipped(skipped)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: fresh == 0 ? null : () => Navigator.pop(context, true),
          child: Text(l10n.importAction),
        ),
      ],
    );
  }
}

/// Asks for the password of an encrypted backup until it opens; pops with
/// the decrypted [ImportData].
class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog({required this.bytes});

  final Uint8List bytes;

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await transfer.parse(widget.bytes, password: _password.text);
      if (mounted) Navigator.pop(context, data);
    } catch (e) {
      if (!mounted) return;
      final wrong =
          e is VaultFailure && e.code == VaultFailureCode.wrongCredentials;
      setState(() {
        _busy = false;
        _error = wrong ? context.l10n.importWrongPassword : failureMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.importFormatBackup),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ErrorBanner(_error),
            Text(l10n.importBackupPasswordBody),
            const SizedBox(height: 12),
            PasswordField(
              controller: _password,
              label: l10n.exportPassword,
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.importOpen),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ export

/// Lets the user pick a format and saves every item to a file.
Future<void> exportToFile(BuildContext context, VaultController controller) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ExportDialog(controller: controller),
  );
}

enum _ExportFormat { backup, csv }

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.controller});

  final VaultController controller;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  static const _minPasswordLength = 10;

  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  _ExportFormat _format = _ExportFormat.backup;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final encrypted = _format == _ExportFormat.backup;
    if (encrypted && !_formKey.currentState!.validate()) return;
    final controller = widget.controller;
    final items = [for (final i in controller.items) i.fields];
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final day = DateTime.now().toIso8601String().substring(0, 10);
      final Uint8List bytes;
      final String name;
      if (encrypted) {
        bytes = await transfer.exportBackup(items, _password.text);
        name = 'arcanum-backup-$day.json';
      } else {
        bytes = utf8.encode(await transfer.exportCsv(items));
        name = 'arcanum-export-$day.csv';
      }
      final saved = await controller.keepUnlocked(
        () => fileDialogs.saveFile(
          name: name,
          mimeType: encrypted ? 'application/json' : 'text/csv',
          bytes: bytes,
        ),
      );
      if (!mounted) return;
      if (!saved) {
        setState(() => _busy = false);
        return;
      }
      Navigator.pop(context);
      _notify(context, context.l10n.exportDone(items.length));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failureMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final encrypted = _format == _ExportFormat.backup;
    final empty = widget.controller.items.isEmpty;
    return AlertDialog(
      title: Text(l10n.exportTitle),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ErrorBanner(_error),
                SegmentedButton<_ExportFormat>(
                  segments: [
                    ButtonSegment(
                      value: _ExportFormat.backup,
                      icon: const Icon(Icons.lock_outline),
                      label: Text(l10n.exportFormatBackup),
                    ),
                    ButtonSegment(
                      value: _ExportFormat.csv,
                      icon: const Icon(Icons.table_rows_outlined),
                      label: Text(l10n.exportFormatCsv),
                    ),
                  ],
                  selected: {_format},
                  onSelectionChanged: _busy
                      ? null
                      : (s) => setState(() => _format = s.first),
                ),
                const SizedBox(height: 16),
                if (empty)
                  Text(l10n.exportEmpty)
                else if (encrypted) ...[
                  Text(l10n.exportBackupHint),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _password,
                    label: l10n.exportPassword,
                    validator: (v) => (v ?? '').length < _minPasswordLength
                        ? l10n.vaultMinLength(_minPasswordLength)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _confirm,
                    label: l10n.exportRepeatPassword,
                    onSubmitted: (_) => _submit(),
                    validator: (v) =>
                        v != _password.text ? l10n.passwordsDontMatch : null,
                  ),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.exportCsvWarning,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy || empty ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.exportAction),
        ),
      ],
    );
  }
}
