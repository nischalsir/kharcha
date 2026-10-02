import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/id_generator.dart';
import '../../models/category_model.dart';
import '../../models/payment_method.dart';
import '../../models/transaction_model.dart';
import '../../providers/ai_insight_provider.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/common/receipt_field.dart';

import 'package:flutter/services.dart';
import '../../widgets/common/glass_back_button.dart';

/// Records a single expense or income.
///
/// The dashboard's "Add Expense" and "Add Income" actions both land here with
/// the type pre-picked, which is why the segmented control is still shown but
/// starts locked to [initialType].
class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key, this.initialType});

  final TransactionType? initialType;

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  /// A transfer is not something you record standalone from the dashboard, so
  /// the picker only offers the two directions the quick actions can start.
  static const List<TransactionType> _formTypes = <TransactionType>[
    TransactionType.expense,
    TransactionType.income,
  ];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  late TransactionType _type;
  PaymentMethod _method = PaymentMethod.cash;
  String? _categoryId;
  DateTime _date = DateTime.now();
  Uint8List? _receipt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? TransactionType.expense;
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  String get _titleLabel =>
      _type == TransactionType.expense ? 'Expense' : 'Income';

  /// Keeps the selected category valid for the current type: switching between
  /// expense and income swaps the available categories, and a category that no
  /// longer exists would silently save as "no category".
  List<CategoryModel> _categoriesFor(TransactionType type) {
    final settings = context.read<AppSettingsProvider>();
    return type == TransactionType.expense
        ? settings.expenseCategories()
        : settings.incomeCategories();
  }

  void _onTypeChanged(TransactionType type) {
    final categories = _categoriesFor(type);
    final stillValid = categories.any((c) => c.id == _categoryId);
    setState(() {
      _type = type;
      if (!stillValid) _categoryId = null;
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final provider = context.read<TransactionProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final amount = parseAmount(_amount.text)!;
    String? categoryName;
    final categories = _categoriesFor(_type);
    final resolvedCategoryId =
        _categoryId ?? (categories.isNotEmpty ? categories.first.id : null);
    for (final category in categories) {
      if (category.id == resolvedCategoryId) {
        categoryName = category.name;
        break;
      }
    }
    // The id is chosen here so the receipt can be stored under it first.
    final id = newId();
    final receipt = _receipt;
    final receiptPath = receipt == null
        ? null
        : await uploadReceipt(receipt, id);
    final ok = await provider.create(
      id: id,
      attachmentPath: receiptPath,
      title: _title.text.trim(),
      amount: amount,
      type: _type,
      occurredAt: _date,
      categoryId: resolvedCategoryId,
      paymentMethod: _method,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      // Let the flame acknowledge the save before this route is popped, so the
      // reaction is already running by the time Home rebuilds.
      context.read<AiInsightProvider>().reactToTransaction(
        isIncome: _type == TransactionType.income,
        amount: amount,
        categoryName: categoryName,
      );
      navigator.pop(true);
      if (receipt != null && receiptPath == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text(receiptNotUploadedMessage)),
        );
      }
      return;
    }
    setState(() => _saving = false);
    showMessage(
      context,
      provider.errorMessage ?? 'Could not save $_titleLabel.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categoriesFor(_type);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
          leading: const GlassBackButton(),title: Text('Add $_titleLabel')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: <Widget>[
              SegmentedButton<TransactionType>(
                segments: <ButtonSegment<TransactionType>>[
                  for (final type in _formTypes)
                    ButtonSegment<TransactionType>(
                      value: type,
                      label: Text(type.label),
                    ),
                ],
                selected: <TransactionType>{_type},
                onSelectionChanged: (value) => _onTypeChanged(value.first),
              ),
              const FieldLabel('Title'),
              TextFormField(
                controller: _title,
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(kMaxTitleLength),
                ],
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: 'e.g. Groceries, Salary'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter a title'
                    : null,
              ),
              const FieldLabel('Amount'),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(hintText: '0'),
                validator: validateAmount,
              ),
              if (categories.isNotEmpty) ...<Widget>[
                const FieldLabel('Category'),
                OptionChips<CategoryModel>(
                  options: categories,
                  selected: categories.firstWhere(
                    (c) => c.id == _categoryId,
                    orElse: () => categories.first,
                  ),
                  labelOf: (c) => c.name,
                  onSelected: (c) => setState(() => _categoryId = c.id),
                ),
              ],
              const FieldLabel('Payment method'),
              OptionChips<PaymentMethod>(
                options: PaymentMethod.values,
                selected: _method,
                labelOf: (m) => m.label,
                onSelected: (m) => setState(() => _method = m),
              ),
              const FieldLabel('Date'),
              DateField(
                value: _date,
                onChanged: (date) {
                  if (date != null) setState(() => _date = date);
                },
              ),
              const FieldLabel('Notes (optional)'),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Notes'),
              ),
              const FieldLabel('Receipt (optional)'),
              ReceiptField(
                value: _receipt,
                onChanged: (bytes) => setState(() => _receipt = bytes),
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: 'Add $_titleLabel',
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
