import 'package:flutter/material.dart';

import '../app/breach_check.dart';
import '../app/messages.dart';
import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import 'item_editor_screen.dart';

/// Checks every password of the vault against known breaches with one
/// button and lists the compromised ones.
class BreachCheckScreen extends StatelessWidget {
  const BreachCheckScreen({super.key, required this.controller});

  final VaultController controller;

  static Iterable<String> passwordsOf(VaultController controller) => controller
      .items
      .where((i) => i.fields.kind == VaultItemKind.login)
      .map((i) => i.fields.password);

  @override
  Widget build(BuildContext context) {
    final checker = BreachScope.maybeOf(context)!;
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final logins = controller.items
            .where(
              (i) =>
                  i.fields.kind == VaultItemKind.login &&
                  i.fields.password.isNotEmpty,
            )
            .toList();
        final compromised =
            logins
                .where((i) => (checker.countFor(i.fields.password) ?? 0) > 0)
                .toList()
              ..sort(
                (a, b) => checker
                    .countFor(b.fields.password)!
                    .compareTo(checker.countFor(a.fields.password)!),
              );
        final last = checker.lastCheck;
        return Scaffold(
          appBar: AppBar(title: Text(l10n.breachTitle)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l10n.breachExplanation),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.breachAutoTitle),
                subtitle: Text(l10n.breachAutoSubtitle),
                value: checker.enabled,
                onChanged: checker.setEnabled,
              ),
              const SizedBox(height: 8),
              Text(
                last == null
                    ? l10n.breachNeverChecked
                    : l10n.breachLastCheck(
                        MaterialLocalizations.of(context)
                            .formatMediumDate(last),
                      ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: checker.running || logins.isEmpty
                    ? null
                    : () => checker.checkAll(passwordsOf(controller)),
                icon: const Icon(Icons.gpp_maybe_outlined),
                label: Text(l10n.breachCheckAll),
              ),
              if (checker.running) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: checker.total == 0
                      ? null
                      : checker.done / checker.total,
                ),
                const SizedBox(height: 8),
                Text(l10n.breachProgress(checker.done, checker.total)),
              ],
              if (!checker.running && checker.failed > 0) ...[
                const SizedBox(height: 16),
                _Notice(
                  icon: Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                  text: l10n.breachSomeFailed(
                    checker.failed,
                    failureMessage(checker.lastError!),
                  ),
                ),
              ],
              if (checker.hasResults && !checker.running) ...[
                const SizedBox(height: 16),
                if (compromised.isEmpty)
                  _Notice(
                    icon: Icons.verified_user_outlined,
                    color: Colors.green,
                    text: l10n.breachNoneFound,
                  )
                else ...[
                  _Notice(
                    icon: Icons.gpp_bad_outlined,
                    color: Theme.of(context).colorScheme.error,
                    text: l10n.breachCompromisedCount(compromised.length),
                  ),
                  const SizedBox(height: 8),
                  for (final item in compromised)
                    _CompromisedTile(
                      item: item,
                      count: checker.countFor(item.fields.password)!,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ItemEditorScreen(
                            controller: controller,
                            item: item,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: color),
      const SizedBox(width: 12),
      Expanded(child: Text(text)),
    ],
  );
}

class _CompromisedTile extends StatelessWidget {
  const _CompromisedTile({
    required this.item,
    required this.count,
    required this.onTap,
  });

  final VaultItem item;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final f = item.fields;
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.gpp_bad_outlined,
          color: Theme.of(context).colorScheme.error,
        ),
        title: Text(f.title.isEmpty ? context.l10n.untitled : f.title),
        subtitle: Text(
          [
            if (f.username.isNotEmpty) f.username,
            context.l10n.breachFound(count),
          ].join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
