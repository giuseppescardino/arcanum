import 'package:flutter/material.dart';

import '../app/android_autofill.dart';
import '../app/breach_check.dart';
import '../app/clipboard.dart';
import '../app/favicons.dart';
import '../app/file_dialogs.dart';
import '../app/groups.dart';
import '../app/messages.dart';
import '../app/quick_access.dart';
import '../app/tools.dart';
import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import 'about.dart';
import 'breach_check_screen.dart';
import 'item_editor_screen.dart';
import 'language_picker.dart';
import 'site_icon.dart';
import 'sync_screen.dart';
import 'transfer_dialogs.dart';
import 'widgets.dart';

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

  /// Root group shown alone, subgroups included: null for all, '' for
  /// ungrouped items.
  String? _groupFilter;

  /// Sections the user opened or closed by hand, by group path; the
  /// others follow [_collapsedByDefault].
  final Map<String, bool> _toggled = {};

  /// With several groups the list opens as a compact index of closed
  /// sections; a single group has nothing to tell apart and stays open.
  bool get _collapsedByDefault => _controller.groups.length > 1;

  bool _isCollapsed(String group) => _toggled[group] ?? _collapsedByDefault;

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
    final match = _visibleItems
        .where((i) => i.fields.password.isNotEmpty)
        .firstOrNull;
    if (match == null) return;
    await copySecret(
      context,
      match.fields.password,
      label: context.l10n.vaultPasswordOf(match.fields.title),
    );
    await QuickAccess.hide();
  }

  /// Visible items as a tree of groups, each followed by its subgroups;
  /// the ungrouped ones (path '') come last. Favorites lead each group,
  /// otherwise the title order from Rust is kept.
  List<_Section> get _sections {
    final q = _query.trim().toLowerCase();
    final filter = _groupFilter;
    final byGroup = <String, List<VaultItem>>{};
    for (final i in _controller.items) {
      final f = i.fields;
      final group = normalizeGroup(f.group);
      if (filter != null &&
          (filter.isEmpty ? group.isNotEmpty : !groupContains(filter, group))) {
        continue;
      }
      final matches =
          q.isEmpty ||
          f.title.toLowerCase().contains(q) ||
          f.username.toLowerCase().contains(q) ||
          group.toLowerCase().contains(q) ||
          f.urls.any((u) => u.toLowerCase().contains(q));
      if (matches) (byGroup[group] ??= []).add(i);
    }
    List<VaultItem> ordered(String group) {
      final items = byGroup[group] ?? const <VaultItem>[];
      return [
        ...items.where((i) => i.fields.favorite),
        ...items.where((i) => !i.fields.favorite),
      ];
    }

    return [
      for (final g in groupTree(byGroup.keys))
        _Section(
          path: g,
          items: ordered(g),
          total: byGroup.entries
              .where((e) => e.key.isNotEmpty && groupContains(g, e.key))
              .fold(0, (sum, e) => sum + e.value.length),
        ),
      if (byGroup.containsKey(''))
        _Section(path: '', items: ordered(''), total: byGroup['']!.length),
    ];
  }

  List<VaultItem> get _visibleItems => [for (final s in _sections) ...s.items];

  void _openEditor([VaultItem? item]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemEditorScreen(
          controller: _controller,
          item: item,
          initialGroup: _groupFilter,
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

  Future<void> _renameGroup(String group) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          _RenameGroupDialog(initial: group, existing: _controller.groups),
    );
    if (name == null || name == group) return;
    await _runGroupAction(() => _controller.renameGroup(group, name));
    // The filter bar only knows root groups.
    if (_groupFilter == group) setState(() => _groupFilter = groupRoot(name));
  }

  Future<void> _deleteGroup(String group) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.vaultDeleteGroupTitle(group)),
        content: Text(context.l10n.vaultDeleteGroupBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.vaultDeleteGroup),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _runGroupAction(() => _controller.renameGroup(group, ''));
    if (_groupFilter == group) setState(() => _groupFilter = null);
  }

  Future<void> _runGroupAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failureMessage(e))));
      }
    }
  }

  void _toggleSection(String group) =>
      setState(() => _toggled[group] = !_isCollapsed(group));

  Widget _buildList(List<_Section> sections) {
    final breach = BreachScope.maybeOf(context);
    final filter = _groupFilter;
    // Headers only help when there is something to tell apart. Inside a
    // root group they show its subgroups; the root's own is left out.
    final showHeaders = _controller.groups.isNotEmpty && filter != '';
    final rootDepth = filter == null ? 0 : 1;
    // A search shows every match, whatever is collapsed.
    final searching = _query.trim().isNotEmpty;
    bool collapsed(String group) =>
        !searching && group != filter && _isCollapsed(group);

    final rows = <Widget>[];
    for (final section in sections) {
      final group = section.path;
      var depth = 0;
      if (showHeaders) {
        if (groupAncestors(group).any(collapsed)) continue;
        if (group != filter) {
          depth = group.isEmpty ? 0 : groupDepth(group) - rootDepth;
          rows.add(
            _GroupHeader(
              name: groupLeaf(group),
              depth: depth,
              count: section.total,
              collapsed: collapsed(group),
              onToggle: () => _toggleSection(group),
              onRename: group.isEmpty ? null : () => _renameGroup(group),
              onDelete: group.isEmpty ? null : () => _deleteGroup(group),
            ),
          );
          if (collapsed(group)) continue;
        }
      }
      for (final item in section.items) {
        rows.add(
          _ItemTile(
            item: item,
            depth: depth,
            compromised: (breach?.countFor(item.fields.password) ?? 0) > 0,
            onTap: () => _openEditor(item),
          ),
        );
      }
    }
    return ListView(padding: const EdgeInsets.only(bottom: 88), children: rows);
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
        await showDialog<void>(
          context: context,
          builder: (_) => _ChangePasswordDialog(controller: _controller),
        );
      case _MenuAction.forgetSecretKey:
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(context.l10n.vaultForgetSecretKeyTitle),
            content: Text(context.l10n.vaultForgetSecretKeyBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(context.l10n.vaultRemove),
              ),
            ],
          ),
        );
        if (ok == true) {
          await _controller.forgetSecretKey();
          _controller.lock();
        }
      case _MenuAction.signOut:
        await _signOut();
    }
  }

  Future<bool> _confirmSignOut(String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.vaultSignOutTitle),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.vaultSignOutConfirm),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _signOut() async {
    final l10n = context.l10n;
    final linked = _controller.linked;
    if (!await _confirmSignOut(
      linked ? l10n.vaultSignOutBodySynced : l10n.vaultSignOutBodyLocal,
    )) {
      return;
    }
    if (linked) {
      // Push pending changes first, so nothing is lost with the vault.
      await _controller.syncNow();
      if (!mounted) return;
      if (_controller.syncError != null &&
          !await _confirmSignOut(l10n.vaultSignOutSyncFailed)) {
        return;
      }
    }
    try {
      await _controller.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failureMessage(e))));
      }
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
        if (_groupFilter != null &&
            _groupFilter!.isNotEmpty &&
            !groups.contains(_groupFilter)) {
          _groupFilter = null;
        }
        final sections = _sections;
        return Scaffold(
          appBar: AppBar(
            title: Text(context.l10n.vaultTitle),
            actions: [
              if (_controller.linked) _SyncButton(controller: _controller),
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
                    child: _MenuEntry(
                      icon: Icons.sync,
                      label: context.l10n.syncTitle,
                    ),
                  ),
                  if (_controller.quickUnlockAvailable)
                    PopupMenuItem(
                      value: _MenuAction.quickUnlock,
                      child: _MenuEntry(
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
                      child: _MenuEntry(
                        icon: Icons.password,
                        label: context.l10n.vaultEnableAutofill,
                      ),
                    ),
                  PopupMenuItem(
                    value: _MenuAction.language,
                    child: _MenuEntry(
                      icon: Icons.language,
                      label: context.l10n.languageTitle,
                    ),
                  ),
                  PopupMenuItem(
                    value: _MenuAction.changePassword,
                    child: _MenuEntry(
                      icon: Icons.key,
                      label: context.l10n.vaultChangeMasterPassword,
                    ),
                  ),
                  if (breach != null)
                    PopupMenuItem(
                      value: _MenuAction.breach,
                      child: _MenuEntry(
                        icon: Icons.gpp_maybe_outlined,
                        label: context.l10n.breachTitle,
                      ),
                    ),
                  PopupMenuItem(
                    value: _MenuAction.import,
                    child: _MenuEntry(
                      icon: Icons.file_download_outlined,
                      label: context.l10n.vaultImport,
                    ),
                  ),
                  if (fileDialogs.canSave)
                    PopupMenuItem(
                      value: _MenuAction.export,
                      child: _MenuEntry(
                        icon: Icons.file_upload_outlined,
                        label: context.l10n.vaultExport,
                      ),
                    ),
                  if (siteIcons != null)
                    PopupMenuItem(
                      value: _MenuAction.siteIcons,
                      child: _MenuEntry(
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
                    child: _MenuEntry(
                      icon: Icons.info_outline,
                      label: context.l10n.vaultAbout,
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: _MenuAction.forgetSecretKey,
                    child: _MenuEntry(
                      icon: Icons.key_off,
                      label: context.l10n.vaultForgetSecretKey,
                    ),
                  ),
                  PopupMenuItem(
                    value: _MenuAction.signOut,
                    child: _MenuEntry(
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
                    _GroupFilterBar(
                      groups: groups,
                      hasUngrouped: _controller.items.any(
                        (i) => i.fields.group.isEmpty,
                      ),
                      selected: _groupFilter,
                      onSelected: (g) => setState(() => _groupFilter = g),
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
              if (_controller.sessionExpired)
                MaterialBanner(
                  leading: const Icon(Icons.sync_problem),
                  content: Text(context.l10n.vaultSessionExpired),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          showReconnectDialog(context, _controller),
                      child: Text(context.l10n.reconnect),
                    ),
                  ],
                ),
              if (breach != null && breach.checkDue)
                MaterialBanner(
                  leading: const Icon(Icons.gpp_maybe_outlined),
                  content: Text(
                    breach.lastCheck == null
                        ? context.l10n.breachReminderFirst
                        : context.l10n.breachReminder,
                  ),
                  actions: [
                    TextButton(
                      onPressed: breach.dismissReminder,
                      child: Text(context.l10n.breachLater),
                    ),
                    TextButton(
                      onPressed: () => _openBreachCheck(start: true),
                      child: Text(context.l10n.breachCheckNow),
                    ),
                  ],
                ),
              Expanded(
                child: sections.isEmpty
                    ? _EmptyState(
                        searching: _query.isNotEmpty || _groupFilter != null,
                      )
                    : _buildList(sections),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Shows sync state; tap to sync now (or reconnect if signed out).
class _SyncButton extends StatelessWidget {
  const _SyncButton({required this.controller});

  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.syncing) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final error = controller.syncError;
    return IconButton(
      tooltip: error ?? context.l10n.syncNow,
      icon: Icon(
        error == null ? Icons.cloud_done_outlined : Icons.sync_problem,
        color: error == null ? null : Theme.of(context).colorScheme.error,
      ),
      onPressed: controller.sessionExpired
          ? () => showReconnectDialog(context, controller)
          : controller.syncNow,
    );
  }
}

/// A group of the list with the items filed directly under it.
class _Section {
  const _Section({
    required this.path,
    required this.items,
    required this.total,
  });

  /// Group path; '' for the ungrouped items.
  final String path;
  final List<VaultItem> items;

  /// Items in this group and in all its subgroups.
  final int total;
}

/// Horizontal chips: all items, one per root group, and the ungrouped
/// ones. Subgroups are reached from the list, under their root.
class _GroupFilterBar extends StatelessWidget {
  const _GroupFilterBar({
    required this.groups,
    required this.hasUngrouped,
    required this.selected,
    required this.onSelected,
  });

  final List<String> groups;
  final bool hasUngrouped;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, String? value, {IconData? icon}) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: icon == null ? null : Icon(icon, size: 18),
        label: Text(label),
        selected: selected == value,
        onSelected: (_) => onSelected(value),
      ),
    );

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
        children: [
          chip(context.l10n.vaultAllGroups, null),
          for (final g in groups) chip(g, g, icon: Icons.folder_outlined),
          if (hasUngrouped) chip(context.l10n.noGroup, ''),
        ],
      ),
    );
  }
}

/// Each level of nesting moves a row this much further in.
EdgeInsetsGeometry _indent(int depth) =>
    EdgeInsetsDirectional.only(start: 16 + 20.0 * depth, end: 24);

enum _GroupAction { rename, delete }

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.name,
    required this.depth,
    required this.count,
    required this.collapsed,
    required this.onToggle,
    this.onRename,
    this.onDelete,
  });

  final String name;

  /// Levels of nesting below the outermost header shown.
  final int depth;

  /// Items in the group, subgroups included.
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: _indent(depth),
      onTap: onToggle,
      leading: Icon(collapsed ? Icons.chevron_right : Icons.expand_more),
      title: Text(
        name.isEmpty ? context.l10n.noGroup : name,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count', style: theme.textTheme.labelMedium),
          if (onRename != null)
            PopupMenuButton<_GroupAction>(
              tooltip: context.l10n.vaultGroupActions,
              onSelected: (a) => switch (a) {
                _GroupAction.rename => onRename!(),
                _GroupAction.delete => onDelete!(),
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _GroupAction.rename,
                  child: Text(context.l10n.vaultRenameGroup),
                ),
                PopupMenuItem(
                  value: _GroupAction.delete,
                  child: Text(context.l10n.vaultDeleteGroup),
                ),
              ],
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _RenameGroupDialog extends StatefulWidget {
  const _RenameGroupDialog({required this.initial, required this.existing});

  final String initial;
  final List<String> existing;

  @override
  State<_RenameGroupDialog> createState() => _RenameGroupDialogState();
}

class _RenameGroupDialogState extends State<_RenameGroupDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = normalizeGroup(_name.text);
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final name = normalizeGroup(_name.text);
    final merges = name != widget.initial && widget.existing.contains(name);
    return AlertDialog(
      title: Text(context.l10n.vaultRenameGroup),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: _name,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: context.l10n.vaultGroupName,
            helperText: merges
                ? context.l10n.vaultGroupMergeHint
                : context.l10n.vaultGroupPathHint,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: name.isEmpty ? null : _submit,
          child: Text(context.l10n.vaultRename),
        ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.onTap,
    this.depth = 0,
    this.compromised = false,
  });

  final VaultItem item;

  /// Nesting of the group header the item sits under.
  final int depth;
  final VoidCallback onTap;

  /// The password was found in a breach by the last check.
  final bool compromised;

  @override
  Widget build(BuildContext context) {
    final f = item.fields;
    final isLogin = f.kind == VaultItemKind.login;
    final subtitle = isLogin
        ? (f.username.isNotEmpty
              ? f.username
              : (f.urls.isNotEmpty ? f.urls.first : ''))
        : f.notes.split('\n').first;

    return ListTile(
      contentPadding: _indent(depth),
      leading: isLogin
          ? SiteIcon(url: f.urls.firstOrNull, fallback: Icons.key)
          : const CircleAvatar(child: Icon(Icons.sticky_note_2_outlined)),
      title: Row(
        children: [
          Flexible(
            child: Text(
              f.title.isEmpty ? context.l10n.untitled : f.title,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (f.favorite) ...[
            const SizedBox(width: 6),
            const Icon(Icons.star, size: 16),
          ],
          if (compromised) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: context.l10n.breachCompromisedTooltip,
              child: Icon(
                Icons.gpp_bad_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
      trailing: isLogin
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (f.totp != null)
                  IconButton(
                    tooltip: context.l10n.vaultCopyTotp,
                    icon: const Icon(Icons.pin_outlined),
                    onPressed: () {
                      final code = tools.totp(f.totp!, DateTime.now());
                      if (code != null) {
                        copySecret(
                          context,
                          code.code,
                          label: context.l10n.vaultTotpCode,
                        );
                      }
                    },
                  ),
                if (f.username.isNotEmpty)
                  IconButton(
                    tooltip: context.l10n.vaultCopyUsername,
                    icon: const Icon(Icons.person_outline),
                    onPressed: () => copySecret(
                      context,
                      f.username,
                      label: context.l10n.username,
                    ),
                  ),
                if (f.password.isNotEmpty)
                  IconButton(
                    tooltip: context.l10n.vaultCopyPassword,
                    icon: const Icon(Icons.copy),
                    onPressed: () => copySecret(
                      context,
                      f.password,
                      label: context.l10n.password,
                    ),
                  ),
              ],
            )
          : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          searching ? context.l10n.vaultNoResults : context.l10n.vaultEmpty,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.controller});

  final VaultController controller;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.changePassword(_current.text, _next.text);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.vaultMasterPasswordChanged)),
      );
    } catch (e) {
      if (mounted) setState(() => _error = failureMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.vaultChangeMasterPassword),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ErrorBanner(_error),
              PasswordField(
                controller: _current,
                label: context.l10n.vaultCurrentPassword,
                autofocus: true,
                validator: (v) =>
                    (v ?? '').isEmpty ? context.l10n.vaultRequired : null,
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _next,
                label: context.l10n.vaultNewPassword,
                validator: (v) => (v ?? '').length < 10
                    ? context.l10n.vaultMinLength(10)
                    : null,
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _confirm,
                label: context.l10n.vaultRepeatNewPassword,
                onSubmitted: (_) => _submit(),
                validator: (v) =>
                    v != _next.text ? context.l10n.passwordsDontMatch : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.l10n.vaultChange),
        ),
      ],
    );
  }
}

/// Popup menu row with a leading icon; [destructive] tints it red.
class _MenuEntry extends StatelessWidget {
  const _MenuEntry({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Flexible(
          child: Text(label, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}
