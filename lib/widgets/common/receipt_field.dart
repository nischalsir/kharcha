import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../services/pasal_image_store.dart';
import '../../services/receipt_store.dart';
import 'form_helpers.dart';
import 'glass_sheet.dart';

/// Shown when a transaction was saved but its receipt would not upload.
const String receiptNotUploadedMessage =
    'Saved, but the receipt could not be uploaded. Open the transaction to '
    'add it again when you are online.';

/// Asks where the receipt picture comes from, then returns it. Null when the
/// user backed out or the picture could not be used (they are told why).
Future<Uint8List?> pickReceiptImage(BuildContext context) async {
  final source = await showGlassSheet<ImageSource>(
    context: context,
    title: 'Receipt photo',
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ActionTile(
          icon: Icons.photo_camera_outlined,
          label: 'Take a photo',
          onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
        ),
        ActionTile(
          icon: Icons.photo_library_outlined,
          label: 'Choose from gallery',
          onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
        ),
      ],
    ),
  );
  if (source == null || !context.mounted) return null;
  try {
    final file = await ImagePicker().pickImage(
      source: source,
      // Enough to read the small print on a bill, and small enough to
      // upload on a slow connection.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length > PasalImageStore.maxBytes) {
      if (context.mounted) {
        showMessage(
          context,
          'That picture is too large. Choose one under 5 MB.',
        );
      }
      return null;
    }
    return bytes;
  } on PlatformException {
    if (context.mounted) {
      showMessage(context, 'Could not open the camera or gallery.');
    }
    return null;
  }
}

/// The receipt row of a transaction form: a button to attach a picture, or
/// the picked picture with a way to take it off again.
class ReceiptField extends StatelessWidget {
  const ReceiptField({super.key, required this.value, required this.onChanged});

  /// The picked picture, not uploaded yet. Null when there is none.
  final Uint8List? value;
  final ValueChanged<Uint8List?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final bytes = await pickReceiptImage(context);
    if (bytes != null) onChanged(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final theme = Theme.of(context);
    final picked = value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _pick(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: glass.fill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: <Widget>[
              if (picked == null)
                Icon(
                  Icons.receipt_long_outlined,
                  size: 20,
                  color: glass.textSecondary,
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    picked,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    cacheWidth: 132,
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  picked == null
                      ? 'Add a photo of the receipt'
                      : 'Receipt added',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: picked == null ? glass.textTertiary : null,
                  ),
                ),
              ),
              if (picked != null)
                IconButton(
                  tooltip: 'Remove receipt',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onChanged(null),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: glass.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uploads a picked receipt for the transaction [transactionId]. Returns the
/// stored path, or null when the upload failed: a receipt that will not
/// upload must not stop the transaction being saved.
Future<String?> uploadReceipt(Uint8List bytes, String transactionId) async {
  try {
    return await const ReceiptStore().upload(
      bytes,
      transactionId: transactionId,
    );
  } catch (_) {
    return null;
  }
}

/// Opens a saved receipt full screen, where it can be pinched to read.
Future<void> showReceipt(BuildContext context, String path) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _ReceiptViewer(path: path),
    ),
  );
}

class _ReceiptViewer extends StatefulWidget {
  const _ReceiptViewer({required this.path});

  final String path;

  @override
  State<_ReceiptViewer> createState() => _ReceiptViewerState();
}

class _ReceiptViewerState extends State<_ReceiptViewer> {
  late final Future<String?> _url = const ReceiptStore().signedUrl(widget.path);

  Widget _unavailable(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        'This receipt cannot be shown right now. Check your connection and '
        'try again.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Colors.white70),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Receipt'),
      ),
      body: Center(
        child: FutureBuilder<String?>(
          future: _url,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator(strokeWidth: 2.4);
            }
            final url = snapshot.data;
            if (url == null) return _unavailable(context);
            return InteractiveViewer(
              maxScale: 5,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const CircularProgressIndicator(strokeWidth: 2.4),
                errorBuilder: (context, _, _) => _unavailable(context),
              ),
            );
          },
        ),
      ),
    );
  }
}
