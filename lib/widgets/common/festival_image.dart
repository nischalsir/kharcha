import 'package:flutter/material.dart';

import '../../services/app_images.dart';

/// A festival photograph served from Cloudinary, sized for where it is shown.
///
/// Cloudinary delivers it as WebP/AVIF at the exact pixel width the widget
/// occupies (`f_auto,q_auto,w_…`), which is far smaller than the bundled
/// 1280px JPEG. The bundled copy stays as the offline fallback, and the
/// festival's icon as the last resort, so the card never shows a broken image.
class FestivalImage extends StatelessWidget {
  const FestivalImage({
    super.key,
    required this.assetPath,
    required this.fallback,
    this.width,
    this.height,
  });

  /// e.g. `assets/images/festivals/holi.jpg`; its file name is the public id.
  final String assetPath;
  final Widget fallback;
  final double? width;
  final double? height;

  static const String _base =
      'https://res.cloudinary.com/dh3rzo7bt/image/upload';

  /// Photos that failed to load this session, so a festival without a picture
  /// is asked for once rather than on every rebuild.
  static final Set<String> _missing = <String>{};

  /// The Cloudinary URL for a bundled festival asset at [pixelWidth].
  static String urlFor(String assetPath, int pixelWidth) {
    final file = assetPath.split('/').last;
    final id = file.contains('.')
        ? file.substring(0, file.lastIndexOf('.'))
        : file;
    return '$_base/f_auto,q_auto,c_fill,g_auto,w_$pixelWidth/kharcha/festivals/$id.jpg';
  }

  /// The picture width asked for when shown [logicalWidth] wide. Rounded up
  /// to a 100px step so nearby sizes share one cached rendition, and so the
  /// preloader and the widget agree on one address.
  static int pixelWidthFor(double logicalWidth, double devicePixelRatio) =>
      ((logicalWidth * devicePixelRatio) / 100).ceil() * 100;

  @override
  Widget build(BuildContext context) {
    final pixelWidth = pixelWidthFor(
      width ?? MediaQuery.sizeOf(context).width,
      MediaQuery.devicePixelRatioOf(context),
    );

    Widget bundled() => Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: BoxFit.cover,
      cacheWidth: pixelWidth,
      errorBuilder: (_, _, _) => fallback,
    );
    if (_missing.contains(assetPath)) return bundled();

    return Image(
      image: ResizeImage.resizeIfNeeded(
        pixelWidth,
        null,
        AppImages.provider(urlFor(assetPath, pixelWidth)),
      ),
      width: width,
      height: height,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
        opacity: sync || frame != null ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: child,
      ),
      errorBuilder: (_, _, _) {
        _missing.add(assetPath);
        return bundled();
      },
    );
  }
}
