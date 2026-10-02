import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category_model.dart';
import '../../models/payment_method.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../repositories/transaction_repository.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_button.dart';
import '../../widgets/common/glass_sheet.dart';
import '../../widgets/common/primary_button.dart';

/// Opens the filters for the transaction list: category, payment method,
/// dates, amount and order. The search box and the type chips stay on the
/// page itself, where they are one tap away.
Future<void> showTransactionFilterSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    title: 'Filter transactions',
    builder: (_) => const _FilterForm(),
  );
}

String transactionSortLabel(TransactionSort sort) => switch (sort) {
  TransactionSort.dateDesc => 'Newest',
  TransactionSort.dateAsc => 'Oldest',
  TransactionSort.amountDesc => 'Highest',
  TransactionSort.amountAsc => 'Lowest',
};

class _FilterForm extends StatefulWidget {
  const _FilterForm();

  @override
  State<_FilterForm> createState() => _FilterFormState();
}

class _FilterFormState extends State<_FilterForm> {
  late TransactionFilter _filter;
  late final TextEditingController _min;
  late final TextEditingController _max;

  static String _plain(double? value) {
    if (value == null) return '';
    return value.toStringAsFixed(2);
  }

  @override
  void initState() {
    super.initState();
    _filter = context.read<TransactionProvider>().filter;
    _min = TextEditingController(text: _plain(_filter.minAmount));
    _max = TextEditingController(text: _plain(_filter.maxAmount));
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  /// The last day shown in the "To" field. The filter keeps the first moment
  /// after the range, so the whole of that day is included.
  DateTime? get _toDay {
    final end = _filter.toExclusive;
    return end == null ? null : DateTime(end.year, end.month, end.day - 1);
  }

  void _apply() {
    final minText = _min.text.trim();
    final maxText = _max.text.trim();
    final min = minText.isEmpty ? null : parseAmount(minText);
    final max = maxText.isEmpty ? null : parseAmount(maxText);
    if ((minText.isNotEmpty && min == null) ||
        (maxText.isNotEmpty && max == null)) {
      showMessage(context, 'Enter a valid amount');
      return;
    }
    if (min != null && max != null && min > max) {
      showMessage(context, 'The smallest amount is more than the largest');
      return;
    }
    final from = _filter.from;
    final to = _filter.toExclusive;
    if (from != null && to != null && !from.isBefore(to)) {
      showMessage(context, 'The first day is after the last day');
      return;
    }
    context.read<TransactionProvider>().applyFilter(
      _filter.copyWith(minAmount: () => min, maxAmount: () => max),
    );
    Navigator.pop(context);
  }

  void _clear() {
    context.read<TransactionProvider>().applyFilter(
      // The type chips are on the page; clearing here leaves them alone.
      TransactionFilter(type: _filter.type),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final List<CategoryModel> categories = context
        .watch<AppSettingsProvider>()
        .categories;
    // A category that was deleted since the filter was set cannot be shown
    // as the dropdown's value.
    final categoryId = categories.any((c) => c.id == _filter.categoryId)
        ? _filter.categoryId
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const FieldLabel('Category'),
        DropdownButtonFormField<String?>(
          key: const ValueKey<String>('filter-category'),
          initialValue: categoryId,
          isExpanded: true,
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All categories'),
            ),
            for (final category in categories)
              DropdownMenuItem<String?>(
                value: category.id,
                child: Text(category.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) => setState(
            () => _filter = _filter.copyWith(categoryId: () => value),
          ),
        ),
        const FieldLabel('Payment method'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            ChoiceChip(
              label: const Text('Any'),
              selected: _filter.paymentMethod == null,
              onSelected: (_) => setState(
                () => _filter = _filter.copyWith(paymentMethod: () => null),
              ),
            ),
            for (final method in PaymentMethod.values)
              ChoiceChip(
                label: Text(method.label),
                selected: _filter.paymentMethod == method,
                onSelected: (_) => setState(
                  () => _filter = _filter.copyWith(paymentMethod: () => method),
                ),
              ),
          ],
        ),
        const FieldLabel('Dates'),
        Row(
          children: <Widget>[
            Expanded(
              child: DateField(
                value: _filter.from,
                hint: 'From',
                allowClear: true,
                onChanged: (date) => setState(
                  () => _filter = _filter.copyWith(from: () => date),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DateField(
                value: _toDay,
                hint: 'To',
                allowClear: true,
                onChanged: (date) => setState(
                  () => _filter = _filter.copyWith(
                    toExclusive: () => date == null
                        ? null
                        : DateTime(date.year, date.month, date.day + 1),
                  ),
                ),
              ),
            ),
          ],
        ),
        const FieldLabel('Amount'),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const ValueKey<String>('filter-min'),
                controller: _min,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(hintText: 'At least'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: const ValueKey<String>('filter-max'),
                controller: _max,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(hintText: 'At most'),
              ),
            ),
          ],
        ),
        const FieldLabel('Order'),
        OptionChips<TransactionSort>(
          options: TransactionSort.values,
          selected: _filter.sort,
          labelOf: transactionSortLabel,
          onSelected: (sort) =>
              setState(() => _filter = _filter.copyWith(sort: sort)),
        ),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            GlassButton(label: 'Clear', onPressed: _clear),
            const SizedBox(width: 10),
            Expanded(
              child: PrimaryButton(label: 'Show results', onPressed: _apply),
            ),
          ],
        ),
      ],
    );
  }
}
