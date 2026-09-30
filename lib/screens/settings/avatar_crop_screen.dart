import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../widgets/common/form_helpers.dart';

/// Square avatar cropper.
///
/// Shows the picked image inside a fixed square viewport that can be panned and
/// zoomed, then rasterises exactly that viewport. It is implemented with plain
/// Flutter (`InteractiveViewer` + `RepaintBoundary`) so no native crop plugin
/// is required and it behaves identically on every platform.
class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  static const double _outputSize = 1024;

  final GlobalKey _boundaryKey = GlobalKey();
  final TransformationController _controller = TransformationController();
  double _cropSize = 0;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy || _cropSize <= 0) return;
    setState(() => _busy = true);
    try {
      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('crop viewport unavailable');
      final pixelRatio = (_outputSize / _cropSize).clamp(1.0, 6.0);
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = data?.buffer.asUint8List();
      if (bytes == null) throw StateError('encode failed');
      if (!mounted) return;
      Navigator.of(context).pop(bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showMessage(context, 'Could not crop the photo. Please try another.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Crop photo'),
        actions: <Widget>[
          TextButton(
            onPressed: _busy ? null : _confirm,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Done',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = math.min(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  _cropSize = math.max(0, size - 32).toDouble();
                  return SizedBox(
                    width: _cropSize,
                    height: _cropSize,
                    child: Stack(
                      children: <Widget>[
                        RepaintBoundary(
                          key: _boundaryKey,
                          child: ClipRect(
                            child: InteractiveViewer(
                              transformationController: _controller,
                              minScale: 1,
                              maxScale: 6,
                              boundaryMargin: EdgeInsets.zero,
                              clipBehavior: Clip.hardEdge,
                              child: SizedBox(
                                width: _cropSize,
                                height: _cropSize,
                                child: Image.memory(
                                  widget.imageBytes,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.9),
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Text(
              'Pinch to zoom and drag to reposition. The square area becomes '
              'your profile picture.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
