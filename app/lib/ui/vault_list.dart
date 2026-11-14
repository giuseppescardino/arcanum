import 'package:flutter/material.dart';

import '../app/breach_check.dart';
import '../app/cards.dart';
import '../app/clipboard.dart';
import '../app/expiry.dart';
import '../app/groups.dart';
import '../app/messages.dart';
import '../app/tools.dart';
import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import 'group_dialogs.dart';
import 'item_kind_sections.dart';
import 'site_icon.dart';

/// Which items the list shows, before the search query narrows them.
sealed class VaultFilter {
  const VaultFilter();
}

class AllItems extends VaultFilter {
  const AllItems();

  @override
  bool operator ==(Object other) => other is AllItems;

  @override
  int get hashCode => (AllItems).hashCode;
}

class FavoriteItems extends VaultFilter {
  const FavoriteItems();

  @override
  bool operator ==(Object other) => other is FavoriteItems;

  @override
  int get hashCode => (FavoriteItems).hashCode;
}

/// Expired or about to expire.
class ExpiringItems extends VaultFilter {
  const ExpiringItems();

  @override
  bool operator ==(Object other) => other is ExpiringItems;

  @override
  int get hashCode => (ExpiringItems).hashCode;
}

/// A root group shown alone, subgroups included; '' is the ungrouped items.
class GroupItems extends VaultFilter {
  const GroupItems(this.root);

  final String root;

  @override
  bool operator ==(Object other) => other is GroupItems && other.root == root;

  @override
  int get hashCode => Object.hash(GroupItems, root);
}

/// Items passing [filter] and [query], in the controller's order.
List<VaultItem> filterItems(
  VaultController c,
  VaultFilter filter,
  String query,
  DateTime now,
) {
  final q = query.trim().toLowerCase();
  bool inFilter(ItemFields f, String group) => switch (filter) {
    AllItems() => true,
    FavoriteItems() => f.favorite,
    ExpiringItems() => switch (expiryState(f, now)) {
      ExpiryState.soon || ExpiryState.expired => true,
      _ => false,
    },
    GroupItems(:final root) =>
      root.isEmpty ? group.isEmpty : groupContains(root, group),
  };
  return [
    for (final i in c.items)
      if (inFilter(i.fields, normalizeGroup(i.fields.group)) &&
          _matches(i.fields, q))
        i,
  ];
}

bool _matches(ItemFields f, String q) =>
    q.isEmpty ||
    f.title.toLowerCase().contains(q) ||
    f.username.toLowerCase().contains(q) ||
    (f.wifi?.ssid.toLowerCase().contains(q) ?? false) ||
    (f.card?.holder.toLowerCase().contains(q) ?? false) ||
    normalizeGroup(f.group).toLowerCase().contains(q) ||
    f.urls.any((u) => u.toLowerCase().contains(q));

/// Visible items as a tree of groups, each followed by its subgroups;
/// the ungrouped ones (path '') come last. Favorites lead each group,
/// otherwise the incoming order is kept.
List<_Section> _sections(List<VaultItem> items) {
  final byGroup = <String, List<VaultItem>>{};
  for (final i in items) {
    (byGroup[normalizeGroup(i.fields.group)] ??= []).add(i);
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

/// [items] (from [filterItems]) in the order the list shows them.
List<VaultItem> inListOrder(List<VaultItem> items) => [
  for (final s in _sections(items)) ...s.items,
];

/// The items passing [filter] and [query], as sections of groups that open
/// and close. Owns which sections are collapsed and the group header menu.
class VaultList extends StatefulWidget {
  const VaultList({
    super.key,
    required this.controller,
    required this.filter,
    required this.query,
    required this.onOpen,
    this.selectedId,
    this.bottomPadding = 0,
  });

  final VaultController controller;
  final VaultFilter filter;
  final String query;

  /// Row tap.
  final void Function(VaultItem item) onOpen;

  /// Highlighted row, wide layout only.
  final String? selectedId;

  /// Room below the last row, e.g. for a floating button.
  final double bottomPadding;

  @override
  State<VaultList> createState() => _VaultListState();
}

class _VaultListState extends State<VaultList> {
  /// Sections the user opened or closed by hand, by group path; the
  /// others follow [_collapsedByDefault].
  final Map<String, bool> _toggled = {};

  VaultController get _controller => widget.controller;

  /// With several groups the list opens as a compact index of closed
  /// sections; a single group has nothing to tell apart and stays open.
  bool get _collapsedByDefault => _controller.groups.length > 1;

  bool _isCollapsed(String group) => _toggled[group] ?? _collapsedByDefault;

  void _toggleSection(String group) =>
      setState(() => _toggled[group] = !_isCollapsed(group));

  Color? _groupColor(String group) {
    final c = _controller.colorOfGroup(group);
    return c == null ? null : Color(c);
  }

  Future<void> _renameGroup(String group) async {
    final name = await showRenameGroupDialog(
      context,
      initial: group,
      existing: _controller.groups,
    );
    if (name == null || name == group) return;
    await _runGroupAction(() => _controller.renameGroup(group, name));
  }

  Future<void> _deleteGroup(String group) async {
    if (!await confirmDeleteGroup(context, group)) return;
    await _runGroupAction(() => _controller.renameGroup(group, ''));
  }

  Future<void> _pickGroupColor(String group) async {
    final picked = await showGroupColorDialog(
      context,
      group: group,
      current: _controller.groupColors[normalizeGroup(group)],
    );
    if (picked == null) return;
    await _runGroupAction(() => _controller.setGroupColor(group, picked.color));
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sections = _sections(
      filterItems(_controller, widget.filter, widget.query, now),
    );
    if (sections.isEmpty) {
      return _EmptyState(
        searching: widget.query.isNotEmpty || widget.filter is! AllItems,
      );
    }
    final breach = BreachScope.maybeOf(context);
    // The root group shown alone, if any.
    final filter = switch (widget.filter) {
      GroupItems(:final root) => root,
      _ => null,
    };
    // Headers only help when there is something to tell apart. Inside a
    // root group they show its subgroups; the root's own is left out.
    final showHeaders = _controller.groups.isNotEmpty && filter != '';
    final rootDepth = filter == null ? 0 : 1;
    // A search, the favorites and the expiring items show every match,
    // whatever is collapsed: they are short lists picked on purpose.
    final expandAll =
        widget.query.trim().isNotEmpty ||
        widget.filter is FavoriteItems ||
        widget.filter is ExpiringItems;
    bool collapsed(String group) =>
        !expandAll && group != filter && _isCollapsed(group);

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
              color: _groupColor(group),
              depth: depth,
              count: section.total,
              collapsed: collapsed(group),
              onToggle: () => _toggleSection(group),
              onRename: group.isEmpty ? null : () => _renameGroup(group),
              onColor: group.isEmpty ? null : () => _pickGroupColor(group),
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
            expiry: expiryState(item.fields, now),
            selected: item.id == widget.selectedId,
            onTap: () => widget.onOpen(item),
          ),
        );
      }
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(8, 4, 8, 8 + widget.bottomPadding),
      children: rows,
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

/// Each level of nesting moves a row this much further in.
EdgeInsetsGeometry _indent(int depth) =>
    EdgeInsetsDirectional.only(start: 8 + 20.0 * depth, end: 4);

enum _GroupAction { rename, color, delete }

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.name,
    required this.depth,
    required this.count,
    required this.collapsed,
    required this.onToggle,
    this.color,
    this.onRename,
    this.onColor,
    this.onDelete,
  });

  final String name;

  /// The group's color, or its nearest colored ancestor's.
  final Color? color;

  /// Levels of nesting below the outermost header shown.
  final int depth;

  /// Items in the group, subgroups included.
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onRename;
  final VoidCallback? onColor;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -3),
      contentPadding: _indent(depth),
      onTap: onToggle,
      leading: Icon(
        collapsed ? Icons.chevron_right : Icons.expand_more,
        size: 18,
        color: muted,
      ),
      title: Row(
        children: [
          Icon(
            collapsed ? Icons.folder_outlined : Icons.folder_open_outlined,
            size: 16,
            color: color ?? muted,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name.isEmpty ? context.l10n.noGroup : name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: theme.textTheme.labelMedium?.copyWith(color: muted),
          ),
          if (onRename != null)
            PopupMenuButton<_GroupAction>(
              tooltip: context.l10n.vaultGroupActions,
              iconSize: 18,
              icon: Icon(Icons.more_horiz, color: muted),
              onSelected: (a) => switch (a) {
                _GroupAction.rename => onRename!(),
                _GroupAction.color => onColor!(),
                _GroupAction.delete => onDelete!(),
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _GroupAction.rename,
                  child: Text(context.l10n.vaultRenameGroup),
                ),
                if (onColor != null)
                  PopupMenuItem(
                    value: _GroupAction.color,
                    child: Text(context.l10n.vaultGroupColor),
                  ),
                PopupMenuItem(
                  value: _GroupAction.delete,
                  child: Text(context.l10n.vaultDeleteGroup),
                ),
              ],
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.onTap,
    required this.expiry,
    this.selected = false,
    this.depth = 0,
    this.compromised = false,
  });

  final VaultItem item;

  /// Nesting of the group header the item sits under.
  final int depth;
  final VoidCallback onTap;

  /// The password was found in a breach by the last check.
  final bool compromised;

  /// Expired or about to expire (see `expiry.dart`).
  final ExpiryState expiry;

  /// The row open in the detail pane.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final f = item.fields;
    final isLogin = f.kind == VaultItemKind.login;
    final card = f.card;
    final wifi = f.wifi;
    final subtitle = switch (f.kind) {
      VaultItemKind.login =>
        f.username.isNotEmpty
            ? f.username
            : (f.urls.isNotEmpty ? f.urls.first : ''),
      VaultItemKind.wifi => wifi?.ssid ?? '',
      VaultItemKind.card => [
        if (card != null && cardBrand(card.number) != CardBrand.unknown)
          cardBrand(card.number).label,
        if (card != null && card.number.isNotEmpty) maskCardNumber(card.number),
        if (card != null && card.expiry.isNotEmpty)
          context.l10n.vaultExpiresOn(card.expiry),
      ].join(' · '),
      _ => f.notes.split('\n').first,
    };

    return ListTile(
      selected: selected,
      contentPadding: _indent(depth),
      leading: switch (f.kind) {
        VaultItemKind.login => SiteIcon(
          url: f.urls.firstOrNull,
          fallback: Icons.key,
        ),
        VaultItemKind.wifi => const ItemAvatar(child: Icon(Icons.wifi)),
        VaultItemKind.card => const ItemAvatar(child: Icon(Icons.credit_card)),
        _ => const ItemAvatar(child: Icon(Icons.sticky_note_2_outlined)),
      },
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
            Icon(Icons.star_rounded, size: 16, color: Colors.amber.shade600),
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
          if (expiry == ExpiryState.expired || expiry == ExpiryState.soon) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: expiry == ExpiryState.expired
                  ? context.l10n.expiryExpiredTooltip
                  : context.l10n.expirySoonTooltip,
              child: Icon(
                expiry == ExpiryState.expired
                    ? Icons.event_busy
                    : Icons.schedule,
                size: 16,
                color: expiry == ExpiryState.expired
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.tertiary,
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
                    icon: const Icon(Icons.content_copy_outlined),
                    onPressed: () => copySecret(
                      context,
                      f.password,
                      label: context.l10n.password,
                    ),
                  ),
              ],
            )
          : wifi != null && wifi.ssid.isNotEmpty
          ? IconButton(
              tooltip: context.l10n.vaultShowWifiQr,
              icon: const Icon(Icons.qr_code_2),
              onPressed: () => showWifiQr(
                context,
                ssid: wifi.ssid,
                security: wifi.security,
                password: f.password,
                hidden: wifi.hidden,
              ),
            )
          : card != null && card.number.isNotEmpty
          ? IconButton(
              tooltip: context.l10n.vaultCopyCardNumber,
              icon: const Icon(Icons.copy),
              onPressed: () => copySecret(
                context,
                card.number,
                label: context.l10n.cardNumber,
              ),
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

/// Horizontal chips: all items, the expiring ones when there are any, one
/// per root group, and the ungrouped ones. Subgroups are reached from the
/// list, under their root.
class GroupFilterBar extends StatelessWidget {
  const GroupFilterBar({
    super.key,
    required this.groups,
    required this.colorOf,
    required this.hasUngrouped,
    required this.selected,
    required this.onSelected,
    this.hasExpiring = false,
  });

  final List<String> groups;
  final Color? Function(String group) colorOf;
  final bool hasUngrouped;

  /// Some item is expired or about to expire: offer the *Scadenze* chip.
  final bool hasExpiring;
  final VaultFilter selected;
  final ValueChanged<VaultFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    Widget chip(
      String label,
      VaultFilter value, {
      IconData? icon,
      Color? color,
    }) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: icon == null ? null : Icon(icon, size: 18, color: color),
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
          chip(context.l10n.vaultAllGroups, const AllItems()),
          if (hasExpiring)
            chip(
              context.l10n.vaultExpiring,
              const ExpiringItems(),
              icon: Icons.event_busy,
            ),
          for (final g in groups)
            chip(
              g,
              GroupItems(g),
              icon: colorOf(g) == null ? Icons.folder_outlined : Icons.folder,
              color: colorOf(g),
            ),
          if (hasUngrouped) chip(context.l10n.noGroup, const GroupItems('')),
        ],
      ),
    );
  }
}
