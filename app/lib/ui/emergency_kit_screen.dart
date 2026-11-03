import 'package:flutter/material.dart';

import '../app/clipboard.dart';
import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import 'widgets.dart';

class EmergencyKitScreen extends StatefulWidget {
  const EmergencyKitScreen({super.key, required this.controller});

  final VaultController controller;

  @override
  State<EmergencyKitScreen> createState() => _EmergencyKitScreenState();
}

class _EmergencyKitScreenState extends State<EmergencyKitScreen> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final secretKey = widget.controller.pendingSecretKey ?? '';
    final l10n = context.l10n;

    return NarrowPage(
      children: [
        const Icon(Icons.key, size: 56),
        const SizedBox(height: 16),
        Text(
          l10n.kitTitle,
          style: text.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.kitIntro,
          style: text.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            secretKey,
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 1.2,
              color: scheme.onSecondaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: Text(l10n.copy),
          onPressed: () =>
              copySecret(context, secretKey, label: l10n.secretKey),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.kitWriteItDown,
          style: text.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _saved,
          onChanged: (v) => setState(() => _saved = v ?? false),
          title: Text(l10n.kitSavedConfirm),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saved ? widget.controller.confirmEmergencyKit : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(l10n.kitContinue),
          ),
        ),
      ],
    );
  }
}
