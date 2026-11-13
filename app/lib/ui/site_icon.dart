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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              bytes,
              width: 20,
              height: 20,
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

/// Rounded-square avatar of a vault item: a light tile with a hairline
/// border, so it stays visible on a highlighted row. [size] is the side.
class ItemAvatar extends StatelessWidget {
  const ItemAvatar({super.key, required this.child, this.size = 36});

  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(size / 4.5),
      ),
      child: IconTheme.merge(
        data: IconThemeData(color: scheme.onSurfaceVariant, size: size / 2),
        child: child,
      ),
    );
  }
}
