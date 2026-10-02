import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/payment_method.dart';
import '../../providers/wallet_provider.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_button.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/glass_sheet.dart';
import '../../widgets/common/page_refresh.dart';
import '../../widgets/common/primary_button.dart';

IconData walletIcon(PaymentMethod method) => switch (method) {
  PaymentMethod.cash => Icons.payments_rounded,
  PaymentMethod.bank => Icons.account_balance_rounded,
  PaymentMethod.esewa => Icons.account_balance_wallet_rounded,
  PaymentMethod.khalti => Icons.account_balance_wallet_rounded,
  PaymentMethod.card => Icons.credit_card_rounded,
  PaymentMethod.qr => Icons.qr_code_rounded,
  PaymentMethod.other => Icons.more_horiz_rounded,
};

/// The payment methods as places money is kept: what each one holds, and
/// moving money from one to another.
class WalletsScreen extends StatelessWidget {
  const WalletsScreen({super.key});

  void _openTransfer(BuildContext context, {PaymentMethod? from}) {
    showGlassSheet<void>(
      context: context,
      title: context.t('Move money', 'पैसा सार्नुहोस्'),
      builder: (_) => _TransferForm(from: from),
    );
  }

  void _openBalance(BuildContext context, Wallet wallet) {
    showGlassSheet<void>(
      context: context,
      title: wallet.label,
      builder: (_) => _BalanceForm(method: wallet.method),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WalletProvider>();
    final theme = Theme.of(context);
    final glass = context.glass;
    final wallets = provider.wallets;
    final total = provider.total;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            context.t('Wallets', 'वालेटहरू'),
            style: theme.textTheme.titleLarge,
          ),
          actions: <Widget>[
            IconButton(
              key: const ValueKey<String>('wallets-transfer'),
              tooltip: context.t('Move money', 'पैसा सार्नुहोस्'),
              onPressed: () => _openTransfer(context),
              icon: const Icon(Icons.swap_horiz_rounded, size: 28),
            ),
          ],
        ),
        body: SafeArea(
          child: PageRefresh(
            pageName: 'Wallets',
            pageNameNe: 'वालेट',
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
              children: <Widget>[
                GlassCard(
                  strong: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.t('In all wallets', 'सबै वालेटमा'),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: glass.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.format(total),
                        key: const ValueKey<String>('wallets-total'),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: total < 0 ? glass.danger : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (final wallet in wallets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GlassCard(
                      key: ValueKey<String>('wallet-${wallet.method.code}'),
                      onTap: () => _openBalance(context, wallet),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.14,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              walletIcon(wallet.method),
                              color: theme.colorScheme.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              wallet.label,
                              style: theme.textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            CurrencyFormatter.format(wallet.balance),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: wallet.balance < 0 ? glass.danger : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Center(
                  child: GlassButton(
                    label: context.t('Move money', 'पैसा सार्नुहोस्'),
                    icon: Icons.swap_horiz_rounded,
                    onPressed: () => _openTransfer(context),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  context.t(
                    'A balance is what you tell the app was in the wallet, '
                        'plus the income and minus the expenses recorded '
                        'against it since. Tap a wallet to set what is really '
                        'in it.',
                    'ब्यालेन्स भनेको तपाईंले वालेटमा भएको भनेको रकम, त्यसपछि '
                        'यसमा लेखिएको आम्दानी जोडेर र खर्च घटाएर आउने रकम हो। '
                        'वालेटमा साँच्चै भएको रकम राख्न वालेट थिच्नुहोस्।',
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: glass.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sets what a wallet really holds right now.
class _BalanceForm extends StatefulWidget {
  const _BalanceForm({required this.method});

  final PaymentMethod method;

  @override
  State<_BalanceForm> createState() => _BalanceFormState();
}

class _BalanceFormState extends State<_BalanceForm> {
  late final TextEditingController _amount;
  bool _saving = false;

  static String _plain(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    final wallet = context.read<WalletProvider>().walletFor(widget.method);
    _amount = TextEditingController(text: _plain(wallet?.balance ?? 0));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Zero is a real balance, and so is an overdrawn one.
    final amount = parseAmount(_amount.text);
    if (amount == null) {
      showMessage(context, 'Enter a valid amount');
      return;
    }
    setState(() => _saving = true);
    final provider = context.read<WalletProvider>();
    final navigator = Navigator.of(context);
    final ok = await provider.setBalance(widget.method, amount);
    if (!mounted) return;
    if (ok) {
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
    final glass = context.glass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(context.t('What is in it now', 'अहिले यसमा कति छ')),
        TextField(
          key: const ValueKey<String>('wallet-balance'),
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: const InputDecoration(hintText: '0'),
        ),
        const SizedBox(height: 8),
        Text(
          context.t(
            'Your transactions are not changed. From here on the balance '
                'follows what you record.',
            'तपाईंका कारोबार बदलिँदैनन्। अबदेखि ब्यालेन्स तपाईंले लेखेको '
                'अनुसार चल्छ।',
          ),
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: glass.textTertiary),
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

/// Moves money from one wallet to another.
class _TransferForm extends StatefulWidget {
  const _TransferForm({this.from});

  final PaymentMethod? from;

  @override
  State<_TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends State<_TransferForm> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  late PaymentMethod _from;
  late PaymentMethod _to;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final wallets = context.read<WalletProvider>().wallets;
    final methods = <PaymentMethod>[for (final w in wallets) w.method];
    _from =
        widget.from ??
        (methods.contains(PaymentMethod.bank)
            ? PaymentMethod.bank
            : (methods.isEmpty ? PaymentMethod.bank : methods.first));
    _to = methods.firstWhere(
      (m) => m != _from,
      orElse: () =>
          _from == PaymentMethod.cash ? PaymentMethod.bank : PaymentMethod.cash,
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final error = validateAmount(_amount.text);
    if (error != null) {
      showMessage(context, error);
      return;
    }
    if (_from == _to) {
      showMessage(
        context,
        context.t('Choose two different wallets', 'दुई फरक वालेट छान्नुहोस्'),
      );
      return;
    }
    setState(() => _saving = true);
    final provider = context.read<WalletProvider>();
    final navigator = Navigator.of(context);
    final ok = await provider.transfer(
      from: _from,
      to: _to,
      amount: parseAmount(_amount.text)!,
      occurredAt: _date,
      notes: blankToNull(_notes.text),
    );
    if (!mounted) return;
    if (ok) {
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
    final wallets = context.watch<WalletProvider>().wallets;
    final labels = <PaymentMethod, String>{
      for (final wallet in wallets) wallet.method: wallet.label,
    };
    // Every method can be chosen, not only the ones shown as wallets: money
    // can be moved into a wallet that has held nothing so far.
    String labelOf(PaymentMethod method) => labels[method] ?? method.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(context.t('From', 'बाट')),
        OptionChips<PaymentMethod>(
          options: PaymentMethod.values,
          selected: _from,
          labelOf: labelOf,
          onSelected: (m) => setState(() => _from = m),
        ),
        FieldLabel(context.t('To', 'मा')),
        OptionChips<PaymentMethod>(
          options: PaymentMethod.values,
          selected: _to,
          labelOf: labelOf,
          onSelected: (m) => setState(() => _to = m),
        ),
        FieldLabel(context.t('Amount', 'रकम')),
        TextField(
          key: const ValueKey<String>('transfer-amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0'),
        ),
        FieldLabel(context.t('Date', 'मिति')),
        DateField(
          value: _date,
          onChanged: (date) {
            if (date != null) setState(() => _date = date);
          },
        ),
        FieldLabel(context.t('Notes (optional)', 'टिप्पणी (ऐच्छिक)')),
        TextField(
          controller: _notes,
          decoration: InputDecoration(hintText: context.t('Notes', 'टिप्पणी')),
        ),
        const SizedBox(height: 8),
        Text(
          context.t(
            'A transfer is not spending or income. It only changes which '
                'wallet the money is in.',
            'सारेको पैसा खर्च वा आम्दानी होइन। यसले पैसा कुन वालेटमा छ भन्ने '
                'मात्र बदल्छ।',
          ),
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: context.glass.textTertiary),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: context.t('Move', 'सार्नुहोस्'),
          onPressed: _save,
          isLoading: _saving,
        ),
      ],
    );
  }
}
