import 'dart:async';

import 'package:flutter/material.dart';

import '../app/clipboard.dart';
import '../app/tools.dart';
import '../l10n/l10n.dart';

/// Live 2FA code with a countdown ring; refreshes every second.
class TotpView extends StatefulWidget {
  const TotpView({super.key, required this.secret});

  final String secret;

  @override
  State<TotpView> createState() => _TotpViewState();
}

class _TotpViewState extends State<TotpView> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  static String formatCode(String code) {
    final mid = code.length ~/ 2;
    return '${code.substring(0, mid)} ${code.substring(mid)}';
  }

  @override
  Widget build(BuildContext context) {
    final totp = tools.totp(widget.secret, DateTime.now());
    if (totp == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final urgent = totp.remaining <= 5;
    return Row(
      children: [
        SizedBox.square(
          dimension: 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: totp.remaining / totp.period,
                strokeWidth: 3,
                color: urgent ? scheme.error : scheme.primary,
              ),
              Text(
                '${totp.remaining}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          formatCode(totp.code),
          key: const ValueKey('totp-code'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontFamily: 'monospace',
            letterSpacing: 2,
            color: urgent ? scheme.error : null,
          ),
        ),
        IconButton(
          tooltip: context.l10n.totpCopyCode,
          icon: const Icon(Icons.copy),
          onPressed: () =>
              copySecret(context, totp.code, label: context.l10n.totpCode),
        ),
      ],
    );
  }
}
