import 'package:flutter/material.dart';

import '../app/tools.dart';

class StrengthMeter extends StatelessWidget {
  const StrengthMeter({super.key, required this.password});

  final String password;

  static (String, Color) _style(PasswordStrengthLevel level) => switch (level) {
    PasswordStrengthLevel.veryWeak => ('Molto debole', Colors.red),
    PasswordStrengthLevel.weak => ('Debole', Colors.deepOrange),
    PasswordStrengthLevel.fair => ('Discreta', Colors.amber.shade700),
    PasswordStrengthLevel.strong => ('Forte', Colors.lightGreen.shade700),
    PasswordStrengthLevel.veryStrong => ('Molto forte', Colors.green),
  };

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final s = tools.strength(password);
    final (label, color) = _style(s.level);
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
            '$label · ${s.bits} bit',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
