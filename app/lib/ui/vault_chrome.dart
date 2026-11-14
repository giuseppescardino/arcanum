import 'package:flutter/material.dart';

import '../app/breach_check.dart';
import '../app/vault_controller.dart';
import '../l10n/l10n.dart';
import 'sync_screen.dart';

/// Shows sync state; tap to sync now (or reconnect if signed out).
class VaultSyncButton extends StatelessWidget {
  const VaultSyncButton({super.key, required this.controller});

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

/// Banners above the list: signed-out session and the breach-check reminder.
class VaultBanners extends StatelessWidget {
  const VaultBanners({
    super.key,
    required this.controller,
    required this.onCheckBreachNow,
  });

  final VaultController controller;
  final VoidCallback onCheckBreachNow;

  @override
  Widget build(BuildContext context) {
    final breach = BreachScope.maybeOf(context);
    return Column(
      children: [
        if (controller.sessionExpired)
          MaterialBanner(
            leading: const Icon(Icons.sync_problem),
            content: Text(context.l10n.vaultSessionExpired),
            actions: [
              TextButton(
                onPressed: () => showReconnectDialog(context, controller),
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
                onPressed: () => onCheckBreachNow(),
                child: Text(context.l10n.breachCheckNow),
              ),
            ],
          ),
      ],
    );
  }
}
