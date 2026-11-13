import 'package:flutter/material.dart';

import '../app/android_autofill.dart';
import '../app/breach_check.dart';
import '../app/favicons.dart';
import '../app/file_dialogs.dart';
import '../app/messages.dart';
import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import 'about.dart';
import 'account_actions.dart';
import 'breach_check_screen.dart';
import 'browser_pairing.dart';
import 'language_picker.dart';
import 'sync_screen.dart';
import 'transfer_dialogs.dart';

/// Preferences and account actions, in sections; destructive ones last.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final VaultController controller;

  Future<void> _toggleQuickUnlock(BuildContext context) async {
    try {
      if (controller.quickUnlockEnabled) {
        await controller.disableQuickUnlock();
      } else {
        await controller.enableQuickUnlock();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failureMessage(e))));
      }
    }
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final breach = BreachScope.maybeOf(context);
    final bridge = BridgeScope.maybeOf(context);
    final siteIcons = FaviconScope.maybeOf(context);
    final danger = TextStyle(color: scheme.error);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              children: [
                _SectionHeader(l10n.settingsSecurity),
                if (controller.quickUnlockAvailable)
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: Text(
                      l10n.settingsQuickUnlock(
                        controller.quickUnlock.methodName,
                      ),
                    ),
                    value: controller.quickUnlockEnabled,
                    onChanged: (_) => _toggleQuickUnlock(context),
                  ),
                ListTile(
                  leading: const Icon(Icons.key),
                  title: Text(l10n.vaultChangeMasterPassword),
                  onTap: () => showChangePasswordDialog(context, controller),
                ),
                if (breach != null)
                  ListTile(
                    leading: const Icon(Icons.gpp_maybe_outlined),
                    title: Text(l10n.breachTitle),
                    onTap: () => _push(
                      context,
                      BreachCheckScreen(controller: controller),
                    ),
                  ),
                if (AndroidAutofill.supported)
                  ListTile(
                    leading: const Icon(Icons.password),
                    title: Text(l10n.vaultEnableAutofill),
                    onTap: AndroidAutofill.openSettings,
                  ),
                const Divider(),
                // The entry names its own group: a header would repeat it.
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: Text(l10n.syncTitle),
                  subtitle: _syncHost() == null ? null : Text(_syncHost()!),
                  onTap: () =>
                      _push(context, SyncScreen(controller: controller)),
                ),
                if (bridge != null)
                  ListTile(
                    leading: const Icon(Icons.extension_outlined),
                    title: Text(l10n.browsersTitle),
                    onTap: () =>
                        _push(context, BrowserPairingScreen(server: bridge)),
                  ),
                const Divider(),
                _SectionHeader(l10n.settingsData),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: Text(l10n.vaultImport),
                  onTap: () => importFromFile(context, controller),
                ),
                if (fileDialogs.canSave)
                  ListTile(
                    leading: const Icon(Icons.file_upload_outlined),
                    title: Text(l10n.vaultExport),
                    onTap: () => exportToFile(context, controller),
                  ),
                const Divider(),
                _SectionHeader(l10n.settingsAppearance),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(l10n.languageTitle),
                  subtitle: Text(currentLanguageLabel(context)),
                  onTap: () => showLanguageDialog(context),
                ),
                if (siteIcons != null)
                  SwitchListTile(
                    secondary: const Icon(Icons.image_outlined),
                    title: Text(l10n.settingsSiteIcons),
                    value: siteIcons.enabled,
                    onChanged: siteIcons.setEnabled,
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l10n.vaultAbout),
                  onTap: () => showArcanumAbout(context),
                ),
                const Divider(),
                _SectionHeader(l10n.settingsDangerZone, color: scheme.error),
                ListTile(
                  leading: Icon(Icons.key_off, color: scheme.error),
                  title: Text(l10n.vaultForgetSecretKey, style: danger),
                  onTap: () => forgetSecretKeyOnDevice(context, controller),
                ),
                ListTile(
                  leading: Icon(Icons.logout, color: scheme.error),
                  title: Text(l10n.vaultSignOut, style: danger),
                  onTap: () => signOutOfDevice(context, controller),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Host of the sync server when this vault is linked.
  String? _syncHost() {
    final url = controller.syncInfo?.serverUrl;
    if (!controller.linked || url == null) return null;
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? url : host;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, {this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: color ?? Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
