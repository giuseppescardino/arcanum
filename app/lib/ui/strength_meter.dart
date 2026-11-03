import 'package:flutter/material.dart';

import '../app/tools.dart';
import '../l10n/l10n.dart';

class StrengthMeter extends StatelessWidget {
  const StrengthMeter({super.key, required this.password});

  final String password;

  static (String, Color) _style(
    AppLocalizations l10n,
    PasswordStrengthLevel level,
  ) => switch (level) {
    PasswordStrengthLevel.veryWeak => (l10n.strengthVeryWeak, Colors.red),
    PasswordStrengthLevel.weak => (l10n.strengthWeak, Colors.deepOrange),
    PasswordStrengthLevel.fair => (l10n.strengthFair, Colors.amber.shade700),
    PasswordStrengthLevel.strong => (
      l10n.strengthStrong,
      Colors.lightGreen.shade700,
    ),
    PasswordStrengthLevel.veryStrong => (l10n.strengthVeryStrong, Colors.green),
  };

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final s = tools.strength(password);
    final (label, color) = _style(context.l10n, s.level);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value:
                    (s.level.index + 1) / PasswordStrengthLevel.values.length,
                minHeight: 6,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            context.l10n.strengthLabelWithBits(label, s.bits),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
