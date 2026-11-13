import 'package:flutter/material.dart';

import '../app/breach_check.dart';
import '../app/clipboard.dart';
import '../app/quick_access.dart';
import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import 'breach_check_screen.dart';
import 'item_detail.dart';
import 'item_editor_screen.dart';
import 'settings_screen.dart';
import 'vault_chrome.dart';
import 'vault_list.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, required this.controller});

  final VaultController controller;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
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

  void _openItem(VaultItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ItemDetailScreen(controller: _controller, itemId: item.id),
      ),
    );
  }

  void _newItem() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemEditorScreen(
          controller: _controller,
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

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(controller: _controller),
      ),
    );
  }

  Color? _groupColor(String group) {
    final c = _controller.colorOfGroup(group);
    return c == null ? null : Color(c);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
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
              IconButton(
                tooltip: context.l10n.settingsTitle,
                icon: const Icon(Icons.settings_outlined),
                onPressed: _openSettings,
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
            onPressed: _newItem,
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
                  onOpen: _openItem,
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
