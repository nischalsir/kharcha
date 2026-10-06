import 'package:flutter/material.dart';

import '../../core/theme/motion.dart';
import '../../services/pasal_image_store.dart';
import '../common/skeleton_loader.dart';

/// The picture attached to a pasal credit item, loaded from its storage path.
///
/// Three states, each its own: a still-loading picture is a block the size
/// of the picture; no picture, or one that cannot be reached, is [fallback];
/// and the picture itself fades in over the block it replaces. Loading used
/// to look exactly like "no picture", so a slow one seemed to be missing.
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

  Widget _loading() => Skeleton(
    label: 'Loading picture',
    child: SkeletonLoader(width: widget.size, height: widget.size, radius: 0),
  );

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (url == null) return widget.fallback;
    return FutureBuilder<String?>(
      future: url,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _loading();
        }
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
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            // Already in memory: there is nothing to wait for or fade.
            if (wasSynchronouslyLoaded) return child;
            return AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.medium),
              child: frame == null
                  ? KeyedSubtree(
                      key: const ValueKey<String>('loading'),
                      child: _loading(),
                    )
                  : KeyedSubtree(
                      key: const ValueKey<String>('picture'),
                      child: child,
                    ),
            );
          },
          errorBuilder: (_, _, _) => widget.fallback,
        );
      },
    );
  }
}
