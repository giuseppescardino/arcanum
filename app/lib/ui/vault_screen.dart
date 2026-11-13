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
import 'vault_sidebar.dart';

/// Window width from which the vault shows sidebar, list and item view
/// side by side (the Material "expanded" size class).
const wideLayoutMinWidth = 840.0;

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

  /// The item shown in the wide layout's right-hand column.
  String? _selectedId;

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

  /// Narrow: the item opens full screen.
  void _openItem(VaultItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ItemDetailScreen(controller: _controller, itemId: item.id),
      ),
    );
  }

  /// Wide: the item shows in the right-hand column.
  void _selectItem(VaultItem item) => setState(() => _selectedId = item.id);

  void _editItem(VaultItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemEditorScreen(controller: _controller, item: item),
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

  void _setFilter(VaultFilter f) => setState(() => _filter = f);

  /// Drops a filter or selection that no longer points at anything.
  void _settle({required bool wide, required bool hasExpiring}) {
    // The filtered group may have been renamed or emptied elsewhere.
    if (_filter case GroupItems(:final root)
        when root.isNotEmpty && !_controller.rootGroups.contains(root)) {
      _filter = const AllItems();
    }
    if ((_filter is ExpiringItems && !hasExpiring) ||
        // Favorites live in the sidebar only.
        (_filter is FavoriteItems && !wide)) {
      _filter = const AllItems();
    }
    final selected = _selectedId;
    if (selected != null && !_controller.items.any((i) => i.id == selected)) {
      _selectedId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= wideLayoutMinWidth;
          final hasExpiring = filterItems(
            _controller,
            const ExpiringItems(),
            '',
            DateTime.now(),
          ).isNotEmpty;
          _settle(wide: wide, hasExpiring: hasExpiring);
          return wide ? _wideShell() : _narrowShell(hasExpiring: hasExpiring);
        },
      ),
    );
  }

  /// The same field in both shells; its text and focus live in this state,
  /// so they survive a change of layout.
  Widget _searchField() {
    return TextField(
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
    );
  }

  Widget _banners() => VaultBanners(
    controller: _controller,
    onCheckBreachNow: () => _openBreachCheck(start: true),
  );

  /// Phones and narrow windows: one column, chips for the filter, a FAB.
  Widget _narrowShell({required bool hasExpiring}) {
    final groups = _controller.rootGroups;
    final showChips = groups.isNotEmpty || hasExpiring;
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
          preferredSize: Size.fromHeight(showChips ? 112 : 64),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _searchField(),
              ),
              if (showChips)
                GroupFilterBar(
                  groups: groups,
                  colorOf: _groupColor,
                  hasUngrouped: _controller.items.any(
                    (i) => i.fields.group.isEmpty,
                  ),
                  hasExpiring: hasExpiring,
                  selected: _filter,
                  onSelected: _setFilter,
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
          _banners(),
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
  }

  /// Wide windows: sidebar, list and the selected item side by side.
  Widget _wideShell() {
    final l10n = context.l10n;
    final selected = _selectedId;
    final hint = _SelectHint(text: l10n.vaultSelectItem);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.vaultTitle),
        actions: [
          if (_controller.linked) VaultSyncButton(controller: _controller),
          TextButton.icon(
            onPressed: _controller.lock,
            icon: const Icon(Icons.lock_outline),
            label: Text(l10n.vaultLock),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _newItem,
            icon: const Icon(Icons.add),
            label: Text(l10n.vaultNew),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 232,
            child: VaultSidebar(
              controller: _controller,
              filter: _filter,
              onFilter: _setFilter,
              onSettings: _openSettings,
              onBreachCheck: BreachScope.maybeOf(context) == null
                  ? null
                  : _openBreachCheck,
            ),
          ),
          const VerticalDivider(width: 1),
          SizedBox(
            width: 380,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: _searchField(),
                ),
                _banners(),
                Expanded(
                  child: VaultList(
                    controller: _controller,
                    filter: _filter,
                    query: _query,
                    onOpen: _selectItem,
                    selectedId: selected,
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: selected == null
                ? hint
                : ItemDetailView(
                    controller: _controller,
                    itemId: selected,
                    onEdit: _editItem,
                    empty: hint,
                  ),
          ),
        ],
      ),
    );
  }
}

/// The right-hand column with nothing selected.
class _SelectHint extends StatelessWidget {
  const _SelectHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
