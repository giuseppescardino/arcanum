import 'package:flutter/material.dart';

import '../app/breach_check.dart';
import '../app/messages.dart';
import '../l10n/l10n.dart';

/// Breach state of one password, under the strength meter. Without the
/// automatic check, offers a one-off check: nothing is sent until asked.
class BreachStatus extends StatelessWidget {
  const BreachStatus({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final checker = BreachScope.maybeOf(context);
    if (checker == null || password.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;

    Widget line(Widget icon, String text, {Color? color, Widget? action}) =>
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: small?.copyWith(color: color)),
              ),
              ?action,
            ],
          ),
        );

    if (checker.isChecking(password)) {
      return line(
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        l10n.breachChecking,
      );
    }
    final count = checker.countFor(password);
    if (count != null && count > 0) {
      return line(
        Icon(Icons.gpp_bad_outlined, size: 18, color: scheme.error),
        l10n.breachFound(count),
        color: scheme.error,
      );
    }
    if (count == 0) {
      return line(
        Icon(Icons.verified_user_outlined, size: 18, color: Colors.green),
        l10n.breachNotFound,
      );
    }
    final error = checker.errorFor(password);
    if (error != null) {
      return line(
        Icon(Icons.error_outline, size: 18, color: scheme.error),
        l10n.breachCheckFailed(failureMessage(error)),
        action: TextButton(
          onPressed: () => checker.check(password, force: true),
          child: Text(l10n.breachRetry),
        ),
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: TextButton.icon(
          onPressed: () => checker.check(password),
          icon: const Icon(Icons.gpp_maybe_outlined, size: 18),
          label: Text(l10n.breachCheckThis),
        ),
      ),
    );
  }
}
