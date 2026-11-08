import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/l10n.dart';

/// Shows the app name and the version read at runtime from the build
/// (`version:` in pubspec.yaml), plus Flutter's open-source licenses page.
Future<void> showArcanumAbout(BuildContext context) async {
  final info = await PackageInfo.fromPlatform();
  if (!context.mounted) return;
  final l10n = context.l10n;
  final version = info.buildNumber.isEmpty
      ? info.version
      : '${info.version} (${info.buildNumber})';
  showAboutDialog(
    context: context,
    applicationName: 'Arcanum',
    applicationVersion: l10n.aboutVersion(version),
    applicationIcon: Icon(
      Icons.shield_outlined,
      size: 48,
      color: Theme.of(context).colorScheme.primary,
    ),
    children: [const SizedBox(height: 16), Text(l10n.aboutDescription)],
  );
}
