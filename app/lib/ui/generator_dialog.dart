import 'package:flutter/material.dart';

import '../app/clipboard.dart';
import '../app/tools.dart';
import '../l10n/l10n.dart';
import 'strength_meter.dart';

enum _Mode { password, passphrase }

/// Last choices, kept for the session so the dialog reopens as left.
_Mode _lastMode = _Mode.password;
PasswordGeneratorOptions _lastPassword = const PasswordGeneratorOptions(
  length: 20,
  lowercase: true,
  uppercase: true,
  digits: true,
  symbols: true,
  avoidAmbiguous: true,
);
PassphraseGeneratorOptions _lastPassphrase = const PassphraseGeneratorOptions(
  words: 5,
  separator: '-',
  capitalize: true,
  includeNumber: true,
);

/// Returns the generated value the user chose, or null.
Future<String?> showPasswordGenerator(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const _GeneratorDialog(),
    );

class _GeneratorDialog extends StatefulWidget {
  const _GeneratorDialog();

  @override
  State<_GeneratorDialog> createState() => _GeneratorDialogState();
}

class _GeneratorDialogState extends State<_GeneratorDialog> {
  late _Mode _mode = _lastMode;
  late PasswordGeneratorOptions _pw = _lastPassword;
  late PassphraseGeneratorOptions _pp = _lastPassphrase;
  late String _value = _generate();

  String _generate() => _mode == _Mode.password
      ? tools.generatePassword(_pw)
      : tools.generatePassphrase(_pp);

  void _update(VoidCallback change) {
    setState(() {
      change();
      _lastMode = _mode;
      _lastPassword = _pw;
      _lastPassphrase = _pp;
      _value = _generate();
    });
  }

  PasswordGeneratorOptions _withPw({
    int? length,
    bool? lowercase,
    bool? uppercase,
    bool? digits,
    bool? symbols,
    bool? avoidAmbiguous,
  }) {
    final next = PasswordGeneratorOptions(
      length: length ?? _pw.length,
      lowercase: lowercase ?? _pw.lowercase,
      uppercase: uppercase ?? _pw.uppercase,
      digits: digits ?? _pw.digits,
      symbols: symbols ?? _pw.symbols,
      avoidAmbiguous: avoidAmbiguous ?? _pw.avoidAmbiguous,
    );
    // Keep at least one character set on.
    final any = next.lowercase || next.uppercase || next.digits || next.symbols;
    return any ? next : _pw;
  }

  PassphraseGeneratorOptions _withPp({
    int? words,
    String? separator,
    bool? capitalize,
    bool? includeNumber,
  }) => PassphraseGeneratorOptions(
    words: words ?? _pp.words,
    separator: separator ?? _pp.separator,
    capitalize: capitalize ?? _pp.capitalize,
    includeNumber: includeNumber ?? _pp.includeNumber,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.generatorTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_Mode>(
                segments: [
                  ButtonSegment(
                    value: _Mode.password,
                    label: Text(l10n.password),
                  ),
                  ButtonSegment(
                    value: _Mode.passphrase,
                    label: Text(l10n.generatorPassphrase),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => _update(() => _mode = s.first),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        _value,
                        key: const ValueKey('generated-value'),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.generatorRegenerate,
                      icon: const Icon(Icons.refresh),
                      onPressed: () => _update(() {}),
                    ),
                    IconButton(
                      tooltip: l10n.copy,
                      icon: const Icon(Icons.copy),
                      onPressed: () =>
                          copySecret(context, _value, label: l10n.password),
                    ),
                  ],
                ),
              ),
              StrengthMeter(password: _value),
              const SizedBox(height: 8),
              if (_mode == _Mode.password) ..._passwordOptions(),
              if (_mode == _Mode.passphrase) ..._passphraseOptions(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _value),
          child: Text(l10n.generatorUse),
        ),
      ],
    );
  }

  List<Widget> _passwordOptions() => [
    Row(
      children: [
        Text(context.l10n.generatorLength),
        Expanded(
          child: Slider(
            value: _pw.length.toDouble(),
            min: 8,
            max: 64,
            divisions: 56,
            label: '${_pw.length}',
            onChanged: (v) => _update(() => _pw = _withPw(length: v.round())),
          ),
        ),
        SizedBox(width: 28, child: Text('${_pw.length}')),
      ],
    ),
    _switch(
      context.l10n.generatorLowercase,
      _pw.lowercase,
      (v) => _pw = _withPw(lowercase: v),
    ),
    _switch(
      context.l10n.generatorUppercase,
      _pw.uppercase,
      (v) => _pw = _withPw(uppercase: v),
    ),
    _switch(
      context.l10n.generatorDigits,
      _pw.digits,
      (v) => _pw = _withPw(digits: v),
    ),
    _switch(
      context.l10n.generatorSymbols,
      _pw.symbols,
      (v) => _pw = _withPw(symbols: v),
    ),
    _switch(
      context.l10n.generatorAvoidAmbiguous,
      _pw.avoidAmbiguous,
      (v) => _pw = _withPw(avoidAmbiguous: v),
    ),
  ];

  List<Widget> _passphraseOptions() => [
    Row(
      children: [
        Text(context.l10n.generatorWords),
        Expanded(
          child: Slider(
            value: _pp.words.toDouble(),
            min: 3,
            max: 10,
            divisions: 7,
            label: '${_pp.words}',
            onChanged: (v) => _update(() => _pp = _withPp(words: v.round())),
          ),
        ),
        SizedBox(width: 28, child: Text('${_pp.words}')),
      ],
    ),
    Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: [
        Text(context.l10n.generatorSeparator),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(value: '-', label: Text('-')),
            const ButtonSegment(value: '.', label: Text('.')),
            ButtonSegment(
              value: ' ',
              label: Text(context.l10n.generatorSeparatorSpace),
            ),
            const ButtonSegment(value: '_', label: Text('_')),
          ],
          selected: {_pp.separator},
          onSelectionChanged: (s) =>
              _update(() => _pp = _withPp(separator: s.first)),
        ),
      ],
    ),
    _switch(
      context.l10n.generatorCapitalize,
      _pp.capitalize,
      (v) => _pp = _withPp(capitalize: v),
    ),
    _switch(
      context.l10n.generatorIncludeNumber,
      _pp.includeNumber,
      (v) => _pp = _withPp(includeNumber: v),
    ),
  ];

  Widget _switch(String label, bool value, void Function(bool) apply) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label),
        value: value,
        onChanged: (v) => _update(() => apply(v)),
      );
}
