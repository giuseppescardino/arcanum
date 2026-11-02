import 'package:flutter/material.dart';

import '../app/clipboard.dart';
import '../app/vault_controller.dart';
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

    return NarrowPage(
      children: [
        const Icon(Icons.key, size: 56),
        const SizedBox(height: 16),
        Text(
          'La tua Secret Key',
          style: text.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Insieme alla master password, la Secret Key serve per aprire il '
          'vault su un nuovo dispositivo o dopo una reinstallazione. '
          'È salvata nel portachiavi di questo dispositivo, ma se lo perdi '
          'senza averla annotata i dati sono irrecuperabili.',
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
          label: const Text('Copia'),
          onPressed: () => copySecret(context, secretKey, label: 'Secret Key'),
        ),
        const SizedBox(height: 16),
        Text(
          'Scrivila su carta o salvala in un luogo sicuro, separato dalla '
          'master password.',
          style: text.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _saved,
          onChanged: (v) => setState(() => _saved = v ?? false),
          title: const Text('Ho salvato la Secret Key in un luogo sicuro'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saved ? widget.controller.confirmEmergencyKit : null,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Continua'),
          ),
        ),
      ],
    );
  }
}
