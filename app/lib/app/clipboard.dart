import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const clipboardClearAfter = Duration(seconds: 30);

/// Copies [value] and clears the clipboard after [clipboardClearAfter],
/// unless the user has copied something else in the meantime.
Future<void> copySecret(
  BuildContext context,
  String value, {
  required String label,
}) async {
  await Clipboard.setData(ClipboardData(text: value));
  Timer(clipboardClearAfter, () async {
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current?.text == value) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  });
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$label copiato. Verrà cancellato tra '
          '${clipboardClearAfter.inSeconds} secondi.',
        ),
      ),
    );
  }
}
