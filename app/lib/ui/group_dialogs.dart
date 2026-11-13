import 'package:flutter/material.dart';

import '../app/groups.dart';
import '../l10n/l10n.dart';

/// Asks for a new name (path) for [initial]; null when dismissed.
Future<String?> showRenameGroupDialog(
  BuildContext context, {
  required String initial,
  required List<String> existing,
}) => showDialog<String>(
  context: context,
  builder: (_) => _RenameGroupDialog(initial: initial, existing: existing),
);

/// Asks for a color for [group]; null when dismissed, a choice with a null
/// color for "no color".
Future<GroupColorChoice?> showGroupColorDialog(
  BuildContext context, {
  required String group,
  required int? current,
}) => showDialog<GroupColorChoice>(
  context: context,
  builder: (_) => _GroupColorDialog(group: group, current: current),
);

/// True when the user confirmed deleting [group] (its items stay, ungrouped).
Future<bool> confirmDeleteGroup(BuildContext context, String group) async {
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
  return ok == true;
}

/// Result of [showGroupColorDialog]: a wrapper so "no color" (null) can be
/// told apart from a dismissed dialog.
class GroupColorChoice {
  const GroupColorChoice(this.color);
  final int? color;
}

/// Colors offered for groups: readable on light and dark backgrounds.
const groupPalette = <int>[
  0xFFE53935, // red
  0xFFF4511E, // deep orange
  0xFFFB8C00, // orange
  0xFFFDD835, // yellow
  0xFF7CB342, // light green
  0xFF43A047, // green
  0xFF00897B, // teal
  0xFF039BE5, // light blue
  0xFF1E88E5, // blue
  0xFF3949AB, // indigo
  0xFF8E24AA, // purple
  0xFFD81B60, // pink
  0xFF6D4C41, // brown
  0xFF757575, // grey
];

class _GroupColorDialog extends StatelessWidget {
  const _GroupColorDialog({required this.group, required this.current});

  final String group;
  final int? current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget swatch(int? value) {
      final selected = value == current;
      return Semantics(
        button: true,
        selected: selected,
        label: value == null
            ? context.l10n.vaultGroupColorNone
            : '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        child: InkResponse(
          onTap: () => Navigator.pop(context, GroupColorChoice(value)),
          radius: 24,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value == null ? null : Color(value),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: value == null
                ? Icon(Icons.block, color: theme.colorScheme.outline)
                : selected
                ? const Icon(Icons.check, color: Colors.white)
                : null,
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(context.l10n.vaultGroupColorTitle(groupLeaf(group))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [swatch(null), for (final c in groupPalette) swatch(c)],
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.vaultGroupColorHint,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
      ],
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
