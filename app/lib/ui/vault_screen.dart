import 'package:flutter/material.dart';

import '../app/android_autofill.dart';
import '../app/clipboard.dart';
import '../app/messages.dart';
import '../app/quick_access.dart';
import '../app/tools.dart';
import '../app/vault_controller.dart';
import '../src/rust/api/vault.dart';
import 'item_editor_screen.dart';
import 'sync_screen.dart';
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
  changePassword,
  forgetSecretKey,
}

class _VaultScreenState extends State<VaultScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  /// Group shown alone: null for all, '' for ungrouped items.
  String? _groupFilter;
  final Set<String> _collapsed = {};

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
      label: 'Password di "${match.fields.title}"',
    );
    await QuickAccess.hide();
  }

  /// Visible items split by group: named groups alphabetically, then the
  /// ungrouped ones (key ''). Favorites lead each group, otherwise the
  /// title order from Rust is kept.
  List<MapEntry<String, List<VaultItem>>> get _sections {
    final q = _query.trim().toLowerCase();
    final filter = _groupFilter;
    final matches = _controller.items.where((i) {
      final f = i.fields;
      if (filter != null && f.group != filter) return false;
      return q.isEmpty ||
          f.title.toLowerCase().contains(q) ||
          f.username.toLowerCase().contains(q) ||
          f.group.toLowerCase().contains(q) ||
          f.urls.any((u) => u.toLowerCase().contains(q));
    });
    final byGroup = <String, List<VaultItem>>{};
    for (final i in matches) {
      (byGroup[i.fields.group] ??= []).add(i);
    }
    final names = [
      ..._controller.groups.where(byGroup.containsKey),
      if (byGroup.containsKey('')) '',
    ];
    return [
      for (final g in names)
        MapEntry(g, [
          ...byGroup[g]!.where((i) => i.fields.favorite),
          ...byGroup[g]!.where((i) => !i.fields.favorite),
        ]),
    ];
  }

  List<VaultItem> get _visibleItems => [for (final s in _sections) ...s.value];

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

  Future<void> _renameGroup(String group) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          _RenameGroupDialog(initial: group, existing: _controller.groups),
    );
    if (name == null || name == group) return;
    await _runGroupAction(() => _controller.renameGroup(group, name));
    if (_groupFilter == group) setState(() => _groupFilter = name);
  }

  Future<void> _deleteGroup(String group) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminare il gruppo "$group"?'),
        content: const Text(
          'Gli elementi non vengono eliminati: passano in "Senza gruppo".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina gruppo'),
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

  void _toggleSection(String group) => setState(() {
    if (!_collapsed.remove(group)) _collapsed.add(group);
  });

  Widget _buildList(List<MapEntry<String, List<VaultItem>>> sections) {
    // Headers only help when there is something to tell apart.
    final showHeaders = _groupFilter == null && _controller.groups.isNotEmpty;
    final searching = _query.trim().isNotEmpty;
    final rows = <Widget>[];
    for (final section in sections) {
      final group = section.key;
      final collapsed = !searching && _collapsed.contains(group);
      if (showHeaders) {
        rows.add(
          _GroupHeader(
            name: group,
            count: section.value.length,
            collapsed: collapsed,
            onToggle: () => _toggleSection(group),
            onRename: group.isEmpty ? null : () => _renameGroup(group),
            onDelete: group.isEmpty ? null : () => _deleteGroup(group),
          ),
        );
      }
      if (showHeaders && collapsed) continue;
      for (final item in section.value) {
        rows.add(_ItemTile(item: item, onTap: () => _openEditor(item)));
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
      case _MenuAction.changePassword:
        await showDialog<void>(
          context: context,
          builder: (_) => _ChangePasswordDialog(controller: _controller),
        );
      case _MenuAction.forgetSecretKey:
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Rimuovere la Secret Key?'),
            content: const Text(
              'Al prossimo sblocco su questo dispositivo servirà la Secret Key '
              'dell\'Emergency Kit. Assicurati di averla.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Rimuovi'),
              ),
            ],
          ),
        );
        if (ok == true) {
          await _controller.forgetSecretKey();
          _controller.lock();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final groups = _controller.groups;
        // The filtered group may have been renamed or emptied elsewhere.
        if (_groupFilter != null &&
            _groupFilter!.isNotEmpty &&
            !groups.contains(_groupFilter)) {
          _groupFilter = null;
        }
        final sections = _sections;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Vault'),
            actions: [
              if (_controller.linked) _SyncButton(controller: _controller),
              IconButton(
                tooltip: 'Blocca',
                icon: const Icon(Icons.lock),
                onPressed: _controller.lock,
              ),
              PopupMenuButton<_MenuAction>(
                onSelected: _onMenu,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _MenuAction.sync,
                    child: Text('Sincronizzazione'),
                  ),
                  if (_controller.quickUnlockAvailable)
                    PopupMenuItem(
                      value: _MenuAction.quickUnlock,
                      child: Text(
                        _controller.quickUnlockEnabled
                            ? 'Disattiva sblocco con ${_controller.quickUnlock.methodName}'
                            : 'Attiva sblocco con ${_controller.quickUnlock.methodName}',
                      ),
                    ),
                  if (AndroidAutofill.supported)
                    const PopupMenuItem(
                      value: _MenuAction.autofill,
                      child: Text('Attiva compilazione automatica'),
                    ),
                  PopupMenuItem(
                    value: _MenuAction.changePassword,
                    child: Text('Cambia master password'),
                  ),
                  PopupMenuItem(
                    value: _MenuAction.forgetSecretKey,
                    child: Text('Rimuovi Secret Key da questo dispositivo'),
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
                            ? 'Cerca · Invio copia la password · '
                                  '${QuickAccess.shortcutLabel} da ovunque'
                            : 'Cerca · Invio copia la password',
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
            label: const Text('Nuovo'),
          ),
          body: Column(
            children: [
              if (_controller.sessionExpired)
                MaterialBanner(
                  leading: const Icon(Icons.sync_problem),
                  content: const Text(
                    'La sincronizzazione è sospesa: questo dispositivo deve '
                    'riconnettersi al server.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          showReconnectDialog(context, _controller),
                      child: const Text('Riconnetti'),
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
      tooltip: error ?? 'Sincronizza ora',
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

/// Horizontal chips: all items, one per group, and the ungrouped ones.
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
          chip('Tutti', null),
          for (final g in groups) chip(g, g, icon: Icons.folder_outlined),
          if (hasUngrouped) chip('Senza gruppo', ''),
        ],
      ),
    );
  }
}

enum _GroupAction { rename, delete }

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.name,
    required this.count,
    required this.collapsed,
    required this.onToggle,
    this.onRename,
    this.onDelete,
  });

  final String name;
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
      onTap: onToggle,
      leading: Icon(collapsed ? Icons.chevron_right : Icons.expand_more),
      title: Text(
        name.isEmpty ? 'Senza gruppo' : name,
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
              tooltip: 'Azioni gruppo',
              onSelected: (a) => switch (a) {
                _GroupAction.rename => onRename!(),
                _GroupAction.delete => onDelete!(),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _GroupAction.rename,
                  child: Text('Rinomina gruppo'),
                ),
                PopupMenuItem(
                  value: _GroupAction.delete,
                  child: Text('Elimina gruppo'),
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
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    final merges = name != widget.initial && widget.existing.contains(name);
    return AlertDialog(
      title: const Text('Rinomina gruppo'),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: _name,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Nome',
            helperText: merges
                ? 'Il gruppo esiste già: gli elementi verranno uniti.'
                : null,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: name.isEmpty ? null : _submit,
          child: const Text('Rinomina'),
        ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onTap});

  final VaultItem item;
  final VoidCallback onTap;

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
      leading: CircleAvatar(
        child: Icon(isLogin ? Icons.key : Icons.sticky_note_2_outlined),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              f.title.isEmpty ? '(senza titolo)' : f.title,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (f.favorite) ...[
            const SizedBox(width: 6),
            const Icon(Icons.star, size: 16),
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
                    tooltip: 'Copia codice 2FA',
                    icon: const Icon(Icons.pin_outlined),
                    onPressed: () {
                      final code = tools.totp(f.totp!, DateTime.now());
                      if (code != null) {
                        copySecret(context, code.code, label: 'Codice 2FA');
                      }
                    },
                  ),
                if (f.username.isNotEmpty)
                  IconButton(
                    tooltip: 'Copia nome utente',
                    icon: const Icon(Icons.person_outline),
                    onPressed: () =>
                        copySecret(context, f.username, label: 'Nome utente'),
                  ),
                if (f.password.isNotEmpty)
                  IconButton(
                    tooltip: 'Copia password',
                    icon: const Icon(Icons.copy),
                    onPressed: () =>
                        copySecret(context, f.password, label: 'Password'),
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
          searching ? 'Nessun risultato.' : 'Il vault è vuoto.\nAggiungi la tua prima password con "Nuovo".',
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
        const SnackBar(content: Text('Master password aggiornata.')),
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
      title: const Text('Cambia master password'),
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
                label: 'Password attuale',
                autofocus: true,
                validator: (v) => (v ?? '').isEmpty ? 'Obbligatoria' : null,
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _next,
                label: 'Nuova password',
                validator: (v) =>
                    (v ?? '').length < 10 ? 'Almeno 10 caratteri' : null,
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _confirm,
                label: 'Ripeti nuova password',
                onSubmitted: (_) => _submit(),
                validator: (v) =>
                    v != _next.text ? 'Le password non coincidono' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Cambia'),
        ),
      ],
    );
  }
}
