import 'package:flutter/material.dart';

import '../app/android_autofill.dart';
import '../app/breach_check.dart';
import '../app/clipboard.dart';
import '../app/favicons.dart';
import '../app/file_dialogs.dart';
import '../app/messages.dart';
import '../app/quick_access.dart';
import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import 'about.dart';
import 'account_actions.dart';
import 'breach_check_screen.dart';
import 'browser_pairing.dart';
import 'item_editor_screen.dart';
import 'language_picker.dart';
import 'sync_screen.dart';
import 'transfer_dialogs.dart';
import 'vault_chrome.dart';
import 'vault_list.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, required this.controller});

  final VaultController controller;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

enum _MenuAction {
  sync,
  quickUnlock,
  autofill,
  browsers,
  language,
  changePassword,
  breach,
  import,
  export,
  siteIcons,
  about,
  forgetSecretKey,
  signOut,
}

class _VaultScreenState extends State<VaultScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  VaultFilter _filter = const AllItems();

  VaultController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    QuickAccess.searchRequests.addListener(_focusSearch);
  }

  @override
  void dispose() {
    QuickAccess.searchRequests.removeListener(_focusSearch);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _focusSearch() {
    _search.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _search.text.length,
    );
    _searchFocus.requestFocus();
  }

  /// Enter in the search box: copy the first match's password and, on
  /// desktop, step aside so it can be pasted where it's needed.
  Future<void> _copyFirstMatch() async {
    final match = inListOrder(
      filterItems(_controller, _filter, _query, DateTime.now()),
    ).where((i) => i.fields.password.isNotEmpty).firstOrNull;
    if (match == null) return;
    await copySecret(
      context,
      match.fields.password,
      label: context.l10n.vaultPasswordOf(match.fields.title),
    );
    await QuickAccess.hide();
  }

  void _openEditor([VaultItem? item]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemEditorScreen(
          controller: _controller,
          item: item,
          initialGroup: switch (_filter) {
            GroupItems(:final root) => root,
            _ => null,
          },
        ),
      ),
    );
  }

  void _openBreachCheck({bool start = false}) {
    final checker = BreachScope.maybeOf(context);
    if (start && checker != null) {
      checker.checkAll(BreachCheckScreen.passwordsOf(_controller));
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BreachCheckScreen(controller: _controller),
      ),
    );
  }

  Color? _groupColor(String group) {
    final c = _controller.colorOfGroup(group);
    return c == null ? null : Color(c);
  }

  Future<void> _onMenu(_MenuAction action) async {
    switch (action) {
      case _MenuAction.sync:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SyncScreen(controller: _controller),
          ),
        );
      case _MenuAction.quickUnlock:
        try {
          if (_controller.quickUnlockEnabled) {
            await _controller.disableQuickUnlock();
          } else {
            await _controller.enableQuickUnlock();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(failureMessage(e))));
          }
        }
      case _MenuAction.autofill:
        await AndroidAutofill.openSettings();
      case _MenuAction.browsers:
        final bridge = BridgeScope.maybeOf(context);
        if (bridge == null) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BrowserPairingScreen(server: bridge),
          ),
        );
      case _MenuAction.language:
        await showLanguageDialog(context);
      case _MenuAction.breach:
        _openBreachCheck();
      case _MenuAction.import:
        await importFromFile(context, _controller);
      case _MenuAction.export:
        await exportToFile(context, _controller);
      case _MenuAction.siteIcons:
        final icons = FaviconScope.maybeOf(context);
        await icons?.setEnabled(!icons.enabled);
      case _MenuAction.about:
        await showArcanumAbout(context);
      case _MenuAction.changePassword:
        await showChangePasswordDialog(context, _controller);
      case _MenuAction.forgetSecretKey:
        await forgetSecretKeyOnDevice(context, _controller);
      case _MenuAction.signOut:
        await signOutOfDevice(context, _controller);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final breach = BreachScope.maybeOf(context);
        final siteIcons = FaviconScope.maybeOf(context);
        final groups = _controller.rootGroups;
        // The filtered group may have been renamed or emptied elsewhere.
        if (_filter case GroupItems(:final root)
            when root.isNotEmpty && !groups.contains(root)) {
          _filter = const AllItems();
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(context.l10n.vaultTitle),
            actions: [
              if (_controller.linked) VaultSyncButton(controller: _controller),
              IconButton(
                tooltip: context.l10n.vaultLock,
                icon: const Icon(Icons.lock),
                onPressed: _controller.lock,
              ),
              PopupMenuButton<_MenuAction>(
                onSelected: _onMenu,
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _MenuAction.sync,
                    child: VaultMenuEntry(
                      icon: Icons.sync,
                      label: context.l10n.syncTitle,
                    ),
                  ),
                  if (_controller.quickUnlockAvailable)
                    PopupMenuItem(
                      value: _MenuAction.quickUnlock,
                      child: VaultMenuEntry(
                        icon: _controller.quickUnlockEnabled
                            ? Icons.fingerprint_outlined
                            : Icons.fingerprint,
                        label: _controller.quickUnlockEnabled
                            ? context.l10n.vaultDisableQuickUnlock(
                                _controller.quickUnlock.methodName,
                              )
                            : context.l10n.vaultEnableQuickUnlock(
                                _controller.quickUnlock.methodName,
                              ),
                      ),
                    ),
                  if (AndroidAutofill.supported)
                    PopupMenuItem(
                      value: _MenuAction.autofill,
                      child: VaultMenuEntry(
                        icon: Icons.password,
                        label: context.l10n.vaultEnableAutofill,
                      ),
                    ),
                  if (BridgeScope.maybeOf(context) != null)
                    PopupMenuItem(
                      value: _MenuAction.browsers,
                      child: VaultMenuEntry(
                        icon: Icons.extension_outlined,
                        label: context.l10n.browsersTitle,
                      ),
                    ),
                  PopupMenuItem(
                    value: _MenuAction.language,
                    child: VaultMenuEntry(
                      icon: Icons.language,
                      label: context.l10n.languageTitle,
                    ),
                  ),
                  PopupMenuItem(
                    value: _MenuAction.changePassword,
                    child: VaultMenuEntry(
                      icon: Icons.key,
                      label: context.l10n.vaultChangeMasterPassword,
                    ),
                  ),
                  if (breach != null)
                    PopupMenuItem(
                      value: _MenuAction.breach,
                      child: VaultMenuEntry(
                        icon: Icons.gpp_maybe_outlined,
                        label: context.l10n.breachTitle,
                      ),
                    ),
                  PopupMenuItem(
                    value: _MenuAction.import,
                    child: VaultMenuEntry(
                      icon: Icons.file_download_outlined,
                      label: context.l10n.vaultImport,
                    ),
                  ),
                  if (fileDialogs.canSave)
                    PopupMenuItem(
                      value: _MenuAction.export,
                      child: VaultMenuEntry(
                        icon: Icons.file_upload_outlined,
                        label: context.l10n.vaultExport,
                      ),
                    ),
                  if (siteIcons != null)
                    PopupMenuItem(
                      value: _MenuAction.siteIcons,
                      child: VaultMenuEntry(
                        icon: siteIcons.enabled
                            ? Icons.hide_image_outlined
                            : Icons.image_outlined,
                        label: siteIcons.enabled
                            ? context.l10n.vaultHideSiteIcons
                            : context.l10n.vaultShowSiteIcons,
                      ),
                    ),
                  PopupMenuItem(
                    value: _MenuAction.about,
                    child: VaultMenuEntry(
                      icon: Icons.info_outline,
                      label: context.l10n.vaultAbout,
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: _MenuAction.forgetSecretKey,
                    child: VaultMenuEntry(
                      icon: Icons.key_off,
                      label: context.l10n.vaultForgetSecretKey,
                    ),
                  ),
                  PopupMenuItem(
                    value: _MenuAction.signOut,
                    child: VaultMenuEntry(
                      icon: Icons.logout,
                      label: context.l10n.vaultSignOut,
                      destructive: true,
                    ),
                  ),
                ],
              ),
            ],
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(groups.isEmpty ? 64 : 112),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TextField(
                      controller: _search,
                      focusNode: _searchFocus,
                      onChanged: (v) => setState(() => _query = v),
                      onSubmitted: (_) => _copyFirstMatch(),
                      decoration: InputDecoration(
                        hintText: QuickAccess.active
                            ? context.l10n.vaultSearchHintWithShortcut(
                                QuickAccess.shortcutLabel,
                              )
                            : context.l10n.vaultSearchHint,
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => setState(() {
                                  _search.clear();
                                  _query = '';
                                }),
                              ),
                      ),
                    ),
                  ),
                  if (groups.isNotEmpty)
                    GroupFilterBar(
                      groups: groups,
                      colorOf: _groupColor,
                      hasUngrouped: _controller.items.any(
                        (i) => i.fields.group.isEmpty,
                      ),
                      selected: _filter,
                      onSelected: (f) => setState(() => _filter = f),
                    ),
                ],
              ),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openEditor,
            icon: const Icon(Icons.add),
            label: Text(context.l10n.vaultNew),
          ),
          body: Column(
            children: [
              VaultBanners(
                controller: _controller,
                onCheckBreachNow: () => _openBreachCheck(start: true),
              ),
              Expanded(
                child: VaultList(
                  controller: _controller,
                  filter: _filter,
                  query: _query,
                  onOpen: _openEditor,
                  bottomPadding: 88,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
