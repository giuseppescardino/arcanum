import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/favicons.dart';

/// Avatar of a login: the site's own icon when there is one, otherwise
/// [fallback].
class SiteIcon extends StatefulWidget {
  const SiteIcon({super.key, required this.url, required this.fallback});

  /// First URL of the item; null or empty when it has none.
  final String? url;
  final IconData fallback;

  @override
  State<SiteIcon> createState() => _SiteIconState();
}

class _SiteIconState extends State<SiteIcon> {
  Future<Uint8List?>? _icon;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(SiteIcon old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _resolve();
  }

  void _resolve() {
    final url = widget.url;
    final cache = FaviconScope.maybeOf(context);
    _icon = url == null || url.isEmpty ? null : cache?.iconFor(url);
  }

  @override
  Widget build(BuildContext context) {
    final fallback = ItemAvatar(child: Icon(widget.fallback));
    final icon = _icon;
    if (icon == null) return fallback;
    return FutureBuilder<Uint8List?>(
      future: icon,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return fallback;
        return ItemAvatar(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              bytes,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              // Undecodable icon: same look as a site without one.
              errorBuilder: (_, _, _) => Icon(widget.fallback),
            ),
          ),
        );
      },
    );
  }
}

/// 40 px rounded-square avatar of a vault item. [color] defaults to the
/// theme's secondary container, like the circle avatar it replaces.
class ItemAvatar extends StatelessWidget {
  const ItemAvatar({super.key, required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconTheme.merge(
        data: IconThemeData(color: scheme.onSecondaryContainer),
        child: child,
      ),
    );
  }
}
