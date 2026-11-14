import 'package:flutter/material.dart';

import '../app/language_settings.dart';
import '../l10n/l10n.dart';

/// Language names are shown in their own language, so they stay
/// recognizable whatever the current UI language is.
const _languageNames = {'en': 'English', 'it': 'Italiano'};

/// Name of the language in use, or "System default" when none is picked.
String currentLanguageLabel(BuildContext context) {
  final code = LanguageScope.of(context).locale?.languageCode;
  return _languageNames[code] ?? context.l10n.languageSystem;
}

Future<void> showLanguageDialog(BuildContext context) async {
  final settings = LanguageScope.of(context);
  final l10n = context.l10n;
  final selected = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l10n.languageTitle),
      children: [
        _option(context, '', l10n.languageSystem, settings.locale == null),
        for (final code in LanguageSettings.supported)
          _option(
            context,
            code,
            _languageNames[code]!,
            settings.locale?.languageCode == code,
          ),
      ],
    ),
  );
  if (selected == null) return;
  await settings.select(selected.isEmpty ? null : Locale(selected));
}

Widget _option(BuildContext context, String code, String label, bool on) {
  return SimpleDialogOption(
    onPressed: () => Navigator.pop(context, code),
    child: Row(
      children: [
        Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked),
        const SizedBox(width: 12),
        Text(label),
      ],
    ),
  );
}

class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.l10n.languageTitle,
      icon: const Icon(Icons.translate),
      onPressed: () => showLanguageDialog(context),
    );
  }
}
