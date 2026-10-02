import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/calculator.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/id_generator.dart';
import '../../models/pasal_credit_item_model.dart';
import '../../models/pasal_credit_model.dart';
import '../../providers/pasal_provider.dart';
import '../../services/nepali_date_service.dart';
import '../../services/pasal_image_store.dart';
import '../../widgets/common/calculator_sheet.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/pasal/pasal_item_image.dart';
import '../../widgets/common/glass_back_button.dart';

class AddPasalCreditScreen extends StatefulWidget {
  const AddPasalCreditScreen({
    super.key,
    required this.pasalId,
    this.existing,
    this.existingItems,
  });

  final String pasalId;
  final PasalCredit? existing;
  final List<PasalCreditItem>? existingItems;

  @override
  State<AddPasalCreditScreen> createState() => _AddPasalCreditScreenState();
}

/// One line being edited: what was bought, what it cost, and optionally a
/// picture of it.
class _ItemRow {
  _ItemRow({String? id, String name = '', String price = '', this.imagePath})
    : id = id ?? newId(),
      nameController = TextEditingController(text: name),
      priceController = TextEditingController(text: price);

  final String id;
  final TextEditingController nameController;
  final TextEditingController priceController;

  /// The picture already saved for this item, if any.
  String? imagePath;

  /// A picture chosen in this session that has not been uploaded yet.
  Uint8List? pickedImage;

  bool get hasImage => pickedImage != null || imagePath != null;

  double? get price => parseAmount(priceController.text);

  void dispose() {
    nameController.dispose();
    priceController.dispose();
  }
}

enum _PictureAction { camera, gallery, remove }

class _AddPasalCreditScreenState extends State<AddPasalCreditScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _notes;
  DateTime _purchaseDate = DateTime.now();
  DateTime? _dueDate;
  final List<_ItemRow> _items = <_ItemRow>[];

  /// Saved pictures the user removed or replaced, deleted once the save lands.
  final List<String> _discardedImages = <String>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _purchaseDate = existing?.purchaseDate ?? DateTime.now();
    _dueDate = existing?.dueDate;
    final existingItems = widget.existingItems;
    if (existingItems != null && existingItems.isNotEmpty) {
      for (final item in existingItems) {
        _items.add(
          _ItemRow(
            id: item.id,
            name: item.itemName,
            // Older items were entered as quantity x unit price. What they
            // cost is the same number either way, so that is what is shown.
            price: formatCalculatorResult(item.totalPrice),
            imagePath: item.imagePath,
          ),
        );
      }
    } else {
      _items.add(_ItemRow());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  double get _total =>
      _items.fold<double>(0, (sum, item) => sum + (item.price ?? 0));

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickDate({required bool isDue}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isDue ? (_dueDate ?? now) : _purchaseDate,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() {
      if (isDue) {
        _dueDate = picked;
      } else {
        _purchaseDate = picked;
      }
    });
  }

  Future<void> _editPicture(_ItemRow row) async {
    FocusScope.of(context).unfocus();
    final action = await showModalBottomSheet<_PictureAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, _PictureAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(
                row.hasImage ? 'Choose a different picture' : 'Choose picture',
              ),
              onTap: () => Navigator.pop(context, _PictureAction.gallery),
            ),
            if (row.hasImage)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Remove picture'),
                onTap: () => Navigator.pop(context, _PictureAction.remove),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == _PictureAction.remove) {
      setState(() {
        final saved = row.imagePath;
        if (saved != null) _discardedImages.add(saved);
        row
          ..imagePath = null
          ..pickedImage = null;
      });
      return;
    }

    try {
      final file = await ImagePicker().pickImage(
        source: action == _PictureAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        // Plenty for a picture of a receipt or a product, and small enough
        // to upload on a slow connection.
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > PasalImageStore.maxBytes) {
        _snack('That picture is too large. Choose one under 5 MB.');
        return;
      }
      // The saved picture stays in place until the new one is uploaded, so a
      // failed upload does not lose it.
      setState(() => row.pickedImage = bytes);
    } on PlatformException {
      if (mounted) _snack('Could not open the camera or gallery.');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final validItems = _items
        .where((item) => item.nameController.text.trim().isNotEmpty)
        .toList();
    if (validItems.isEmpty) {
      _snack('Add at least one item.');
      return;
    }
    // Each line is capped, but several lines can still add up to more than
    // the numeric(14,2) total the server stores.
    if (_total > kMaxAmount) {
      _snack('Total is too large.');
      return;
    }
    setState(() => _saving = true);
    final provider = context.read<PasalProvider>();
    const store = PasalImageStore();

    // Pictures first, so the item rows are written with their paths. A
    // picture that will not upload must not stop the credit being saved.
    var failedUploads = 0;
    final replaced = <String>[];
    for (final item in validItems) {
      final picked = item.pickedImage;
      if (picked == null) continue;
      try {
        final previous = item.imagePath;
        item.imagePath = await store.upload(picked, itemId: item.id);
        item.pickedImage = null;
        if (previous != null && previous != item.imagePath) {
          replaced.add(previous);
        }
      } catch (_) {
        failedUploads++;
      }
    }

    final now = DateTime.now();
    final existing = widget.existing;
    final credit = PasalCredit(
      id: existing?.id ?? newId(),
      pasalId: widget.pasalId,
      title: _title.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      purchaseDate: _purchaseDate,
      dueDate: _dueDate,
      totalAmount: _total,
      paidAmount: existing?.paidAmount ?? 0,
      status: existing?.status ?? PasalCreditStatus.unpaid,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    final items = <PasalCreditItem>[
      for (var i = 0; i < validItems.length; i++)
        PasalCreditItem(
          id: validItems[i].id,
          creditId: credit.id,
          itemName: validItems[i].nameController.text.trim(),
          // One entry, one price: stored as a quantity of one so records
          // written before and after this screen changed add up the same way.
          quantity: 1,
          unit: 'pcs',
          unitPrice: validItems[i].price ?? 0,
          imagePath: validItems[i].imagePath,
          sortOrder: i,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    final ok = await provider.saveCredit(credit, items);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      _snack(provider.errorMessage ?? 'Could not save credit.');
      return;
    }
    for (final path in <String>[..._discardedImages, ...replaced]) {
      // Best effort, and only after the rows no longer point at them.
      store.remove(path);
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context, true);
    if (failedUploads > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failedUploads == 1
                ? 'Saved, but the picture could not be uploaded. '
                      'Open the credit to try again.'
                : 'Saved, but $failedUploads pictures could not be '
                      'uploaded. Open the credit to try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dates = context.read<NepaliDateService>();
    final isEdit = widget.existing != null;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const GlassBackButton(),
        title: Text(isEdit ? 'Edit Credit' : 'Add Pasal Credit'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: <Widget>[
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(kMaxTitleLength),
                ],
                decoration: const InputDecoration(labelText: 'Purchase title'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: GlassCard(
                      onTap: () => _pickDate(isDue: false),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Purchase Date',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Text(
                            dates.format(_purchaseDate, style: BsFormat.short),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassCard(
                      onTap: () => _pickDate(isDue: true),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Due Date',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Text(
                            _dueDate == null
                                ? 'Optional'
                                : dates.format(
                                    _dueDate!,
                                    style: BsFormat.short,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text('Items', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (var i = 0; i < _items.length; i++)
                Padding(
                  // Keyed by item, so removing one never hands its picture or
                  // text to the row that slides into its place.
                  key: ValueKey<String>(_items[i].id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ItemEditor(
                    row: _items[i],
                    onChanged: () => setState(() {}),
                    onPicture: () => _editPicture(_items[i]),
                    onRemove: _items.length > 1
                        ? () => setState(() {
                            final saved = _items[i].imagePath;
                            if (saved != null) _discardedImages.add(saved);
                            _items[i].dispose();
                            _items.removeAt(i);
                          })
                        : null,
                  ),
                ),
              TextButton.icon(
                onPressed: () => setState(() => _items.add(_ItemRow())),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add item'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const SizedBox(height: 16),
              GlassCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      'Total',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      CurrencyFormatter.format(_total),
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: isEdit ? 'Save Changes' : 'Add Credit',
                onPressed: _saving ? null : _save,
                isLoading: _saving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One item: its picture on the left, name and price beside it.
class _ItemEditor extends StatelessWidget {
  const _ItemEditor({
    required this.row,
    required this.onChanged,
    required this.onPicture,
    this.onRemove,
  });

  final _ItemRow row;
  final VoidCallback onChanged;
  final VoidCallback onPicture;
  final VoidCallback? onRemove;

  static const double _pictureSize = 64;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _PictureButton(row: row, size: _pictureSize, onTap: onPicture),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: <Widget>[
                TextFormField(
                  controller: row.nameController,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  inputFormatters: <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(kMaxTitleLength),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Item name',
                    hintText: 'e.g. Rice',
                  ),
                  onChanged: (_) => onChanged(),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: row.priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Price',
                    hintText: '0',
                    suffixIcon: CalculatorButton(
                      controller: row.priceController,
                      onResult: onChanged,
                    ),
                  ),
                  // Only an item that is actually being added needs a price.
                  validator: (value) => row.nameController.text.trim().isEmpty
                      ? null
                      : validateAmount(value),
                  onChanged: (_) => onChanged(),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove item',
              icon: const Icon(Icons.close_rounded, size: 20),
            )
          else
            const SizedBox(width: 6),
        ],
      ),
    );
  }
}

/// The square picture slot: empty with a camera icon, or the chosen/saved
/// picture with a small edit badge. Tapping opens the picture options.
class _PictureButton extends StatelessWidget {
  const _PictureButton({
    required this.row,
    required this.size,
    required this.onTap,
  });

  final _ItemRow row;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final picked = row.pickedImage;

    final empty = ColoredBox(
      color: glass.fill,
      child: Center(
        child: Icon(
          Icons.add_a_photo_outlined,
          size: 22,
          color: glass.textSecondary,
        ),
      ),
    );

    return Semantics(
      button: true,
      label: row.hasImage ? 'Change item picture' : 'Add item picture',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: picked != null
                    ? Image.memory(
                        picked,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => empty,
                      )
                    : PasalItemImage(
                        path: row.imagePath,
                        size: size,
                        fallback: empty,
                      ),
              ),
              if (row.hasImage)
                Positioned(
                  right: 3,
                  bottom: 3,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.edit_rounded,
                      size: 11,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
