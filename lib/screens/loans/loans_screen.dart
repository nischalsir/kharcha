import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/loan_model.dart';
import '../../models/payment_method.dart';
import '../../providers/loan_provider.dart';
import '../../repositories/loan_repository.dart';
import '../../services/flamey_controller.dart';
import '../../services/nepali_date_service.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/glass_sheet.dart';
import '../../widgets/common/page_refresh.dart';
import '../../widgets/common/primary_button.dart';

/// Loans being repaid in monthly instalments: what is still owed, what each
/// one costs in interest, and when the next instalment is due.
class LoansScreen extends StatelessWidget {
  const LoansScreen({super.key});

  void _openForm(BuildContext context) {
    showGlassSheet<void>(
      context: context,
      title: context.t('Add a loan', 'ऋण थप्नुहोस्'),
      builder: (_) => const _LoanForm(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LoanProvider>();
    final theme = Theme.of(context);
    final glass = context.glass;
    final loans = provider.loans;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            context.t('Loans & EMI', 'ऋण र किस्ता'),
            style: theme.textTheme.titleLarge,
          ),
          actions: <Widget>[
            IconButton(
              key: const ValueKey<String>('loans-add'),
              tooltip: context.t('Add a loan', 'ऋण थप्नुहोस्'),
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.add_circle_rounded, size: 28),
            ),
          ],
        ),
        body: SafeArea(
          child: PageRefresh(
            pageName: 'Loans',
            pageNameNe: 'ऋण',
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
              children: <Widget>[
                if (loans.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: EmptyState(
                      icon: Icons.account_balance_outlined,
                      title: context.t('No loans', 'ऋण छैन'),
                      message: context.t(
                        'Add a loan to see its monthly instalment, the '
                            'interest it costs and what is left to pay.',
                        'मासिक किस्ता, लाग्ने ब्याज र तिर्न बाँकी रकम हेर्न '
                            'ऋण थप्नुहोस्।',
                      ),
                      actionLabel: context.t('Add a loan', 'ऋण थप्नुहोस्'),
                      onAction: () => _openForm(context),
                    ),
                  )
                else ...<Widget>[
                  GlassCard(
                    strong: true,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: _Figure(
                            label: context.t('Still owed', 'तिर्न बाँकी'),
                            value: CurrencyFormatter.format(
                              provider.totalOutstanding,
                            ),
                          ),
                        ),
                        Container(width: 1, height: 36, color: glass.border),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _Figure(
                            label: context.t('Each month', 'हरेक महिना'),
                            value: CurrencyFormatter.format(
                              provider.monthlyTotal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final item in loans)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GlassCard(
                        key: ValueKey<String>('loan-${item.loan.id}'),
                        onTap: () => showGlassSheet<void>(
                          context: context,
                          title: item.loan.name,
                          builder: (_) => _LoanDetails(id: item.loan.id),
                        ),
                        child: _LoanCard(item: item),
                      ),
                    ),
                  Center(
                    child: Text(
                      context.t(
                        'Each loan has a monthly reminder on the Payments '
                            'page, under Recurring.',
                        'हरेक ऋणको मासिक सम्झना भुक्तानी पृष्ठको आवर्तीमा हुन्छ।',
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: glass.textTertiary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: context.glass.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        // Shrinks rather than cuts: a figure with its last digits missing
        // is worse than a smaller one.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({required this.item});

  final LoanStatus item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final dates = context.read<NepaliDateService>();
    final loan = item.loan;
    final overdue = item.isOverdue(DateTime.now());
    final color = overdue ? glass.warning : glass.success;
    final due = item.nextDue;

    final String status;
    if (item.isPaidOff) {
      status = context.t('Paid off', 'चुक्ता भयो');
    } else if (due == null) {
      status = context.t(
        '${item.remainingInstalments} instalments left',
        '${L10n.neNumber(item.remainingInstalments)} किस्ता बाँकी',
      );
    } else {
      status = overdue
          ? context.t(
              'Was due ${dates.format(due, style: BsFormat.short)}',
              '${dates.format(due, style: BsFormat.short)} मा तिर्नुपर्ने थियो',
            )
          : context.t(
              'Next on ${dates.format(due, style: BsFormat.short)}',
              'अर्को ${dates.format(due, style: BsFormat.short)} मा',
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                loan.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              context.t(
                '${CurrencyFormatter.format(loan.emiAmount)} / month',
                '${CurrencyFormatter.format(loan.emiAmount)} / महिना',
              ),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (loan.lender != null)
          Text(
            loan.lender!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: glass.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: item.fraction.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: glass.fill,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: <Widget>[
              Text(
                context.t(
                  '${item.paid} of ${loan.tenureMonths} paid · '
                      '${CurrencyFormatter.format(item.outstanding)} owed',
                  '${L10n.neNumber(loan.tenureMonths)} मध्ये '
                      '${L10n.neNumber(item.paid)} तिरियो · '
                      '${CurrencyFormatter.format(item.outstanding)} बाँकी',
                ),
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                status,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: overdue ? glass.warning : glass.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One loan in full, with paying an instalment and deleting.
class _LoanDetails extends StatefulWidget {
  const _LoanDetails({required this.id});

  final String id;

  @override
  State<_LoanDetails> createState() => _LoanDetailsState();
}

class _LoanDetailsState extends State<_LoanDetails> {
  bool _busy = false;

  Future<void> _pay() async {
    setState(() => _busy = true);
    final provider = context.read<LoanProvider>();
    final flamey = FlameyController.maybeOf(context);
    final ok = await provider.payInstalment(widget.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      showMessage(
        context,
        provider.errorMessage ??
            context.t('Could not save', 'सुरक्षित गर्न सकिएन'),
      );
      return;
    }
    final paidOff = provider.statusOf(widget.id)?.isPaidOff ?? false;
    flamey?.send(paidOff ? FlameyEvent.goalReached : FlameyEvent.taskCompleted);
  }

  Future<void> _delete() async {
    final provider = context.read<LoanProvider>();
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.t('Delete this loan?', 'यो ऋण मेटाउने?')),
        content: Text(
          dialogContext.t(
            'The loan and its monthly reminder are removed. Instalments you '
                'already recorded stay in your payments.',
            'ऋण र यसको मासिक सम्झना हट्छ। पहिले लेखिएका किस्ता भुक्तानीमा '
                'रहन्छन्।',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.t('Cancel', 'रद्द गर्नुहोस्')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text(dialogContext.t('Delete', 'मेटाउनुहोस्')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await provider.delete(widget.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final item = context.watch<LoanProvider>().statusOf(widget.id);
    if (item == null) return const SizedBox.shrink();
    final glass = context.glass;
    final theme = Theme.of(context);
    final loan = item.loan;

    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: glass.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    String rate(double value) => value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: Text(
            CurrencyFormatter.format(item.outstanding),
            style: theme.textTheme.headlineSmall,
          ),
        ),
        Center(
          child: Text(
            context.t('still owed', 'तिर्न बाँकी साँवा'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: glass.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        line(
          context.t('Borrowed', 'लिएको ऋण'),
          CurrencyFormatter.format(loan.principal),
        ),
        line(
          context.t('Interest a year', 'वार्षिक ब्याज'),
          '${rate(loan.annualRate)}%',
        ),
        line(
          context.t('Instalment', 'किस्ता'),
          CurrencyFormatter.format(loan.emiAmount),
        ),
        line(
          context.t('Instalments paid', 'तिरेका किस्ता'),
          '${item.paid} / ${loan.tenureMonths}',
        ),
        line(
          context.t('Interest in all', 'जम्मा ब्याज'),
          CurrencyFormatter.format(loan.totalInterest),
        ),
        line(
          context.t('Left to pay, with interest', 'ब्याजसहित तिर्न बाँकी'),
          CurrencyFormatter.format(item.leftToPay),
        ),
        if (!item.isPaidOff)
          line(
            context.t('Interest in the next one', 'अर्को किस्तामा ब्याज'),
            CurrencyFormatter.format(loan.interestIn(item.paid + 1)),
          ),
        const SizedBox(height: 12),
        if (!item.isPaidOff)
          PrimaryButton(
            key: const ValueKey<String>('loan-pay'),
            label: context.t(
              'Mark this month’s instalment paid',
              'यस महिनाको किस्ता तिरेको चिन्ह लगाउनुहोस्',
            ),
            onPressed: _pay,
            isLoading: _busy,
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _busy ? null : _delete,
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: Text(context.t('Delete loan', 'ऋण मेटाउनुहोस्')),
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
        ),
      ],
    );
  }
}

class _LoanForm extends StatefulWidget {
  const _LoanForm();

  @override
  State<_LoanForm> createState() => _LoanFormState();
}

class _LoanFormState extends State<_LoanForm> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _lender = TextEditingController();
  final TextEditingController _principal = TextEditingController();
  final TextEditingController _rate = TextEditingController();
  final TextEditingController _months = TextEditingController();
  final TextEditingController _paid = TextEditingController();
  final TextEditingController _emi = TextEditingController();
  PaymentMethod _method = PaymentMethod.bank;
  DateTime _due = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final field in <TextEditingController>[_principal, _rate, _months]) {
      field.addListener(_refresh);
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final field in <TextEditingController>[
      _name,
      _lender,
      _principal,
      _rate,
      _months,
      _paid,
      _emi,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  double? get _rateValue {
    final text = _rate.text.trim();
    if (text.isEmpty) return 0;
    final value = double.tryParse(text);
    return value == null || !value.isFinite ? null : value;
  }

  /// The instalment the figures typed so far work out to, if they are
  /// complete enough to say.
  double? get _computedEmi {
    final principal = parseAmount(_principal.text);
    final months = int.tryParse(_months.text.trim());
    final rate = _rateValue;
    if (principal == null || principal <= 0) return null;
    if (months == null || months < 1 || rate == null || rate < 0) return null;
    return emiFor(principal: principal, annualRate: rate, months: months);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMessage(context, context.t('Enter a name', 'नाम लेख्नुहोस्'));
      return;
    }
    final error = validateAmount(_principal.text);
    if (error != null) {
      showMessage(context, error);
      return;
    }
    final rate = _rateValue;
    final months = int.tryParse(_months.text.trim());
    if (rate == null || months == null) {
      showMessage(
        context,
        context.t(
          'Enter the interest and the number of months',
          'ब्याज र महिना सङ्ख्या लेख्नुहोस्',
        ),
      );
      return;
    }
    final paid = _paid.text.trim().isEmpty
        ? 0
        : int.tryParse(_paid.text.trim());
    if (paid == null) {
      showMessage(context, 'Enter a valid number of instalments');
      return;
    }
    double? emi;
    if (_emi.text.trim().isNotEmpty) {
      emi = parseAmount(_emi.text);
      if (emi == null || emi <= 0) {
        showMessage(context, 'Enter a valid amount');
        return;
      }
    }
    setState(() => _saving = true);
    final provider = context.read<LoanProvider>();
    final navigator = Navigator.of(context);
    final ok = await provider.create(
      name: name,
      lender: blankToNull(_lender.text),
      principal: parseAmount(_principal.text)!,
      annualRate: rate,
      tenureMonths: months,
      firstDueDate: _due,
      paidBefore: paid,
      emiAmount: emi,
      paymentMethod: _method,
    );
    if (!mounted) return;
    if (ok) {
      FlameyController.maybeOf(context)?.send(FlameyEvent.taskCompleted);
      navigator.pop();
    } else {
      setState(() => _saving = false);
      showMessage(
        context,
        provider.errorMessage ??
            context.t('Could not save', 'सुरक्षित गर्न सकिएन'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final computed = _computedEmi;
    const number = TextInputType.numberWithOptions(decimal: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(context.t('Name', 'नाम')),
        TextField(
          key: const ValueKey<String>('loan-name'),
          controller: _name,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(LoanRepository.maxNameLength),
          ],
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: context.t('e.g. Bike loan', 'जस्तै बाइक ऋण'),
          ),
        ),
        FieldLabel(context.t('Lender (optional)', 'ऋणदाता (ऐच्छिक)')),
        TextField(
          controller: _lender,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(80),
          ],
          decoration: InputDecoration(
            hintText: context.t('Bank or person', 'बैंक वा व्यक्ति'),
          ),
        ),
        FieldLabel(context.t('Amount borrowed', 'लिएको रकम')),
        TextField(
          key: const ValueKey<String>('loan-principal'),
          controller: _principal,
          keyboardType: number,
          decoration: const InputDecoration(hintText: '0'),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FieldLabel(context.t('Interest % a year', 'वार्षिक ब्याज %')),
                  TextField(
                    key: const ValueKey<String>('loan-rate'),
                    controller: _rate,
                    keyboardType: number,
                    decoration: const InputDecoration(hintText: '0'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FieldLabel(context.t('Months', 'महिना')),
                  TextField(
                    key: const ValueKey<String>('loan-months'),
                    controller: _months,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '12'),
                  ),
                ],
              ),
            ),
          ],
        ),
        FieldLabel(
          context.t(
            'Monthly instalment (leave empty to work it out)',
            'मासिक किस्ता (हिसाब गर्न खाली छोड्नुहोस्)',
          ),
        ),
        TextField(
          key: const ValueKey<String>('loan-emi'),
          controller: _emi,
          keyboardType: number,
          decoration: InputDecoration(
            hintText: computed == null
                ? '0'
                : CurrencyFormatter.number(computed, decimals: 2),
          ),
        ),
        FieldLabel(
          context.t('Next instalment due', 'अर्को किस्ता तिर्ने मिति'),
        ),
        DateField(
          value: _due,
          onChanged: (date) {
            if (date != null) setState(() => _due = date);
          },
        ),
        FieldLabel(
          context.t(
            'Instalments already paid (optional)',
            'पहिले तिरेका किस्ता (ऐच्छिक)',
          ),
        ),
        TextField(
          controller: _paid,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '0'),
        ),
        FieldLabel(context.t('Paid from', 'कहाँबाट तिर्ने')),
        OptionChips<PaymentMethod>(
          options: PaymentMethod.values,
          selected: _method,
          labelOf: (m) => m.label,
          onSelected: (m) => setState(() => _method = m),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: context.t('Save', 'सुरक्षित गर्नुहोस्'),
          onPressed: _save,
          isLoading: _saving,
        ),
      ],
    );
  }
}
