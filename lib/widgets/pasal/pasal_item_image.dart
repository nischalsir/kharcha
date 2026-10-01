import 'package:flutter/material.dart';

import '../../services/pasal_image_store.dart';

/// The picture attached to a pasal credit item, loaded from its storage path.
/// Shows [fallback] while loading, when there is no picture, and when it
/// cannot be reached.
class PasalItemImage extends StatefulWidget {
  const PasalItemImage({
    super.key,
    required this.path,
    required this.size,
    required this.fallback,
  });

  final String? path;
  final double size;
  final Widget fallback;

  @override
  State<PasalItemImage> createState() => _PasalItemImageState();
}

class _PasalItemImageState extends State<PasalItemImage> {
  Future<String?>? _url;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(PasalItemImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _resolve();
  }

  void _resolve() {
    final path = widget.path;
    _url = path == null || path.isEmpty
        ? null
        : const PasalImageStore().signedUrl(path);
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (url == null) return widget.fallback;
    return FutureBuilder<String?>(
      future: url,
      builder: (context, snapshot) {
        final value = snapshot.data;
        if (value == null) return widget.fallback;
        final pixels = (widget.size * MediaQuery.devicePixelRatioOf(context))
            .round();
        return Image.network(
          value,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          cacheWidth: pixels,
          errorBuilder: (_, _, _) => widget.fallback,
        );
      },
    );
  }
}
