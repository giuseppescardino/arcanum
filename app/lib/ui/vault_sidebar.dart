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
    final now = DateTime.now();
    int count(VaultFilter f) => filterItems(controller, f, '', now).length;

    Widget entry(
      VaultFilter value,
      String label,
      Widget icon, {
      required int count,
    }) => ListTile(
      dense: true,
      leading: icon,
      title: Text(label, overflow: TextOverflow.ellipsis),
      trailing: Text('$count', style: theme.textTheme.labelMedium),
      selected: filter == value,
      onTap: () => onFilter(value),
    );

    final expiring = count(const ExpiringItems());
    final ungrouped = count(const GroupItems(''));
    return Column(
      key: const Key('vaultSidebar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              entry(
                const AllItems(),
                l10n.vaultAllGroups,
                const Icon(Icons.inventory_2_outlined),
                count: controller.items.length,
              ),
              entry(
                const FavoriteItems(),
                l10n.vaultFavorites,
                const Icon(Icons.star_outline),
                count: count(const FavoriteItems()),
              ),
              if (expiring > 0)
                entry(
                  const ExpiringItems(),
                  l10n.vaultExpiring,
                  const Icon(Icons.event_busy),
                  count: expiring,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  l10n.vaultGroups,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              for (final g in controller.rootGroups)
                entry(
                  GroupItems(g),
                  g,
                  Icon(Icons.folder, color: _colorOf(g)),
                  count: count(GroupItems(g)),
                ),
              if (ungrouped > 0)
                entry(
                  const GroupItems(''),
                  l10n.noGroup,
                  const Icon(Icons.folder_off_outlined),
                  count: ungrouped,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (onBreachCheck != null)
          ListTile(
            dense: true,
            leading: const Icon(Icons.gpp_maybe_outlined),
            title: Text(l10n.breachTitle),
            onTap: onBreachCheck,
          ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.settings_outlined),
          title: Text(l10n.settingsTitle),
          onTap: onSettings,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Color? _colorOf(String group) {
    final c = controller.colorOfGroup(group);
    return c == null ? null : Color(c);
  }
}
