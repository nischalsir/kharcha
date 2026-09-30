import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/currency_formatter.dart';
import '../../core/utils/id_generator.dart';
import '../../models/pasal_credit_item_model.dart';
import '../../models/pasal_credit_model.dart';
import '../../providers/pasal_provider.dart';
import '../../services/nepali_date_service.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/common/form_helpers.dart';
import 'package:flutter/services.dart';

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

class _ItemRow {
  _ItemRow({
    String? id,
    String name = '',
    String qty = '',
    String unit = 'pcs',
    String price = '',
  }) : id = id ?? newId(),
       nameController = TextEditingController(text: name),
       qtyController = TextEditingController(text: qty),
       unitController = TextEditingController(text: unit),
       priceController = TextEditingController(text: price);

  final String id;
  final TextEditingController nameController;
  final TextEditingController qtyController;
  final TextEditingController unitController;
  final TextEditingController priceController;

  double get quantity => parseAmount(qtyController.text) ?? 0;
  double get unitPrice => parseAmount(priceController.text) ?? 0;
  double get total => quantity * unitPrice;

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    unitController.dispose();
    priceController.dispose();
  }
}

class _AddPasalCreditScreenState extends State<AddPasalCreditScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _notes;
  DateTime _purchaseDate = DateTime.now();
  DateTime? _dueDate;
  final List<_ItemRow> _items = <_ItemRow>[];
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
            qty: item.quantity == item.quantity.roundToDouble()
                ? item.quantity.toStringAsFixed(0)
                : item.quantity.toString(),
            unit: item.unit,
            price: item.unitPrice == item.unitPrice.roundToDouble()
                ? item.unitPrice.toStringAsFixed(0)
                : item.unitPrice.toString(),
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

  double get _total => _items.fold<double>(0, (sum, item) => sum + item.total);

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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final validItems = _items
        .where((item) => item.nameController.text.trim().isNotEmpty)
        .toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add at least one item.')));
      return;
    }
    // Each line is capped, but quantity x price across several lines can
    // still overflow the numeric(14,2) total the server stores.
    if (_total > kMaxAmount) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Total is too large.')));
      return;
    }
    setState(() => _saving = true);
    final provider = context.read<PasalProvider>();
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
          quantity: validItems[i].quantity,
          unit: validItems[i].unitController.text.trim().isEmpty
              ? 'pcs'
              : validItems[i].unitController.text.trim(),
          unitPrice: validItems[i].unitPrice,
          sortOrder: i,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    final ok = await provider.saveCredit(credit, items);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      final message = provider.errorMessage ?? 'Could not save credit.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dates = context.read<NepaliDateService>();
    final isEdit = widget.existing != null;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(isEdit ? 'Edit Credit' : 'Add Pasal Credit')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: <Widget>[
              TextFormField(
                controller: _title,
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
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ItemEditor(
                    row: _items[i],
                    onChanged: () => setState(() {}),
                    onRemove: _items.length > 1
                        ? () => setState(() {
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

class _ItemEditor extends StatelessWidget {
  const _ItemEditor({
    required this.row,
    required this.onChanged,
    this.onRemove,
  });

  final _ItemRow row;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: row.nameController,
                  decoration: const InputDecoration(labelText: 'Item name'),
                  onChanged: (_) => onChanged(),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: row.qtyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Qty'),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.unitController,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Unit price'),
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              CurrencyFormatter.format(row.total),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}
