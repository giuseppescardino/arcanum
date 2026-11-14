import 'package:flutter/material.dart';

import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import 'vault_list.dart';

/// Wide layout, left column: the filters with their counts, then the
/// compromised-passwords check and the settings.
class VaultSidebar extends StatelessWidget {
  const VaultSidebar({
    super.key,
    required this.controller,
    required this.filter,
    required this.onFilter,
    required this.onSettings,
    this.onBreachCheck,
  });

  final VaultController controller;

  /// The filter the list shows, highlighted here.
  final VaultFilter filter;
  final ValueChanged<VaultFilter> onFilter;
  final VoidCallback onSettings;

  /// Opens the compromised-passwords screen; null hides the entry.
  final VoidCallback? onBreachCheck;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    int count(VaultFilter f) => filterItems(controller, f, '', now).length;

    Widget entry(
      VaultFilter value,
      String label,
      IconData icon, {
      required int count,
      Color? iconColor,
    }) => SidebarEntry(
      icon: icon,
      iconColor: iconColor,
      label: label,
      count: count,
      selected: filter == value,
      onTap: () => onFilter(value),
    );

    final expiring = count(const ExpiringItems());
    final ungrouped = count(const GroupItems(''));
    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: Column(
        key: const Key('vaultSidebar'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
              children: [
                entry(
                  const AllItems(),
                  l10n.vaultAllGroups,
                  Icons.key_outlined,
                  count: controller.items.length,
                ),
                entry(
                  const FavoriteItems(),
                  l10n.vaultFavorites,
                  Icons.star_outline,
                  count: count(const FavoriteItems()),
                ),
                if (expiring > 0)
                  entry(
                    const ExpiringItems(),
                    l10n.vaultExpiring,
                    Icons.event_busy_outlined,
                    count: expiring,
                    iconColor: scheme.tertiary,
                  ),
                _SidebarHeading(l10n.vaultGroups),
                for (final g in controller.rootGroups)
                  entry(
                    GroupItems(g),
                    g,
                    Icons.folder_outlined,
                    iconColor: _colorOf(g),
                    count: count(GroupItems(g)),
                  ),
                if (ungrouped > 0)
                  entry(
                    const GroupItems(''),
                    l10n.noGroup,
                    Icons.folder_off_outlined,
                    count: ungrouped,
                  ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (onBreachCheck != null)
                  SidebarEntry(
                    icon: Icons.gpp_maybe_outlined,
                    label: l10n.breachTitle,
                    onTap: onBreachCheck!,
                  ),
                SidebarEntry(
                  icon: Icons.settings_outlined,
                  label: l10n.settingsTitle,
                  onTap: onSettings,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color? _colorOf(String group) {
    final c = controller.colorOfGroup(group);
    return c == null ? null : Color(c);
  }
}

/// One compact row of the sidebar: icon, label and an optional count.
class SidebarEntry extends StatelessWidget {
  const SidebarEntry({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.count,
    this.selected = false,
  });

  final IconData icon;
  final Color? iconColor;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Semantics(
            selected: selected,
            button: true,
            child: SizedBox(
              height: 36,
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Icon(
                    icon,
                    size: 18,
                    color:
                        iconColor ?? (selected ? fg : scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: fg,
                        fontWeight: selected ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                  if (count != null)
                    Text(
                      '$count',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: selected ? fg : scheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarHeading extends StatelessWidget {
  const _SidebarHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
