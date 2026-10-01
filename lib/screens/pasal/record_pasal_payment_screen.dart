import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/payment_method.dart';
import '../../providers/pasal_provider.dart';
import '../../services/nepali_date_service.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/common/form_helpers.dart';
import '../../services/flamey_controller.dart';

class RecordPasalPaymentScreen extends StatefulWidget {
  const RecordPasalPaymentScreen({
    super.key,
    required this.pasalId,
    this.creditId,
  });

  final String pasalId;
  final String? creditId;

  @override
  State<RecordPasalPaymentScreen> createState() =>
      _RecordPasalPaymentScreenState();
}

class _RecordPasalPaymentScreenState extends State<RecordPasalPaymentScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  DateTime _paidAt = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _remaining {
    final provider = context.read<PasalProvider>();
    if (widget.creditId != null) {
      return provider.creditById(widget.creditId!)?.remainingAmount ?? 0;
    }
    return provider.balanceFor(widget.pasalId).remaining;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidAt,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _paidAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = parseAmount(_amountController.text) ?? 0;
    setState(() => _saving = true);
    final provider = context.read<PasalProvider>();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();
    final ok = widget.creditId != null
        ? await provider.addPayment(
            creditId: widget.creditId!,
            amount: amount,
            method: _method,
            paidAt: _paidAt,
            notes: notes,
          )
        : await provider.payAcrossCredits(
            pasalId: widget.pasalId,
            amount: amount,
            method: _method,
            paidAt: _paidAt,
            notes: notes,
          );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      // Paying off a tab is a job done; Flamey notices.
      FlameyController.maybeOf(context)?.send(FlameyEvent.taskCompleted);
      Navigator.pop(context, true);
    } else {
      final message = provider.errorMessage ?? 'Could not record payment.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dates = context.read<NepaliDateService>();
    final glass = context.glass;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Record Payment')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: <Widget>[
              GlassCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      'Remaining',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: glass.textSecondary),
                    ),
                    Text(
                      CurrencyFormatter.format(_remaining),
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount'),
                validator: validateAmount,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final method in PaymentMethod.values)
                    ChoiceChip(
                      label: Text(method.label),
                      selected: _method == method,
                      onSelected: (_) => setState(() => _method = method),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              GlassCard(
                onTap: _pickDate,
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text('Payment Date'),
                    Text(dates.format(_paidAt, style: BsFormat.short)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Record Payment',
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
