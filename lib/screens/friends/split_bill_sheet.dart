import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/split_math.dart';
import '../../models/payment_method.dart';
import '../../models/transaction_model.dart';
import '../../providers/friend_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_sheet.dart';
import '../../widgets/common/primary_button.dart';

/// Splits a bill the user paid between friends: each chosen friend ends up
/// owing their equal share, in the same ledger as any other money lent.
Future<void> showSplitBillSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    title: 'Split a bill',
    builder: (_) => const _SplitBillForm(),
  );
}

class _SplitBillForm extends StatefulWidget {
  const _SplitBillForm();

  @override
  State<_SplitBillForm> createState() => _SplitBillFormState();
}

class _SplitBillFormState extends State<_SplitBillForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final Set<String> _chosen = <String>{};
  bool _includeMe = true;
  bool _addExpense = true;
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // The shares shown below follow the amount as it is typed.
    _amount.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _amount.removeListener(_refresh);
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  int get _people => _chosen.length + (_includeMe ? 1 : 0);

  /// How the typed amount divides between the chosen friends and the user.
  BillSplit get _split {
    final total = parseAmount(_amount.text);
    return splitBill(
      total ?? 0,
      friends: _chosen.length,
      includePayer: _includeMe,
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showMessage(context, 'Enter what the bill was for');
      return;
    }
    final error = validateAmount(_amount.text);
    if (error != null) {
      showMessage(context, error);
      return;
    }
    if (_chosen.isEmpty) {
      showMessage(context, 'Choose at least one friend');
      return;
    }
    final split = _split;
    final friendShares = split.friends;
    if (friendShares.any((share) => share <= 0)) {
      showMessage(context, 'The bill is too small to split this many ways');
      return;
    }
    setState(() => _saving = true);
    final friends = context.read<FriendProvider>();
    final transactions = context.read<TransactionProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ids = _chosen.toList();
    final ok = await friends.splitBill(
      title: title,
      shares: <String, double>{
        for (var i = 0; i < ids.length; i++) ids[i]: friendShares[i],
      },
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _saving = false);
      showMessage(context, friends.errorMessage ?? 'Could not save');
      return;
    }
    var expenseSaved = true;
    if (_includeMe && _addExpense && split.mine > 0) {
      expenseSaved = await transactions.create(
        title: title,
        amount: split.mine,
        type: TransactionType.expense,
        occurredAt: DateTime.now(),
        paymentMethod: _method,
        notes:
            'My share of a bill split ${_people == 2 ? 'with' : 'between'} '
            '$_people people',
      );
    }
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            expenseSaved
                ? '${ids.length} ${ids.length == 1 ? 'friend owes' : 'friends owe'} '
                      'you their share.'
                : 'The shares were saved, but your own expense could not be '
                      'added.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final theme = Theme.of(context);
    final friends = context.watch<FriendProvider>().allFriends;
    final split = _split;

    if (friends.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Add a friend first, then you can split a bill with them.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: glass.textSecondary,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const FieldLabel('What was it for?'),
        TextField(
          key: const ValueKey<String>('split-title'),
          controller: _title,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(kMaxTitleLength),
          ],
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Dinner, Taxi'),
        ),
        const FieldLabel('Total you paid'),
        TextField(
          key: const ValueKey<String>('split-amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0'),
        ),
        const FieldLabel('Split with'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final friend in friends)
              FilterChip(
                key: ValueKey<String>('split-friend-${friend.id}'),
                label: Text(friend.name),
                selected: _chosen.contains(friend.id),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _chosen.add(friend.id);
                  } else {
                    _chosen.remove(friend.id);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 6),
        SwitchListTile.adaptive(
          key: const ValueKey<String>('split-include-me'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('I am sharing it too'),
          subtitle: const Text('Off when you paid only for the others'),
          value: _includeMe,
          onChanged: (value) => setState(() => _includeMe = value),
        ),
        if (split.friends.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              color: glass.fill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    // Without the payer in the split a paisa or two may not
                    // divide, and the first friends carry it.
                    'Each friend owes you ${split.isEven ? '' : 'about '}'
                    '${_money(split.friends.last)}',
                    key: const ValueKey<String>('split-each'),
                    style: theme.textTheme.titleSmall,
                  ),
                  if (_includeMe)
                    Text(
                      'Your share is ${_money(split.mine)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: glass.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (_includeMe) ...<Widget>[
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Add my share to my expenses'),
            value: _addExpense,
            onChanged: (value) => setState(() => _addExpense = value),
          ),
          if (_addExpense) ...<Widget>[
            const FieldLabel('Paid with'),
            OptionChips<PaymentMethod>(
              options: PaymentMethod.values,
              selected: _method,
              labelOf: (m) => m.label,
              onSelected: (m) => setState(() => _method = m),
            ),
          ],
        ],
        const SizedBox(height: 20),
        PrimaryButton(label: 'Split', onPressed: _save, isLoading: _saving),
      ],
    );
  }

  /// Whole rupees are shown plainly; a share with paisa shows them.
  static String _money(double value) => CurrencyFormatter.format(
    value,
    decimals: value == value.roundToDouble() ? 0 : 2,
  );
}
