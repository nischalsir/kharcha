import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/id_generator.dart';
import '../../models/payment_method.dart';
import '../../models/recurring_payment_model.dart';
import '../../models/transaction_model.dart';
import '../../providers/ai_insight_provider.dart';
import '../../providers/recurring_payment_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../repositories/transaction_repository.dart';
import '../../services/nepali_date_service.dart';
import '../../services/receipt_store.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_button.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/glass_sheet.dart';
import '../../widgets/common/grouped_list.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/common/receipt_field.dart';
import '../../widgets/common/segmented_switch.dart';
import '../../widgets/common/skeleton_loader.dart';
import '../../widgets/pasal/pasal_item_image.dart';
import 'transaction_filter_sheet.dart';

import 'package:flutter/services.dart';

import '../../widgets/common/page_refresh.dart';

const List<TransactionType> _formTypes = <TransactionType>[
  TransactionType.expense,
  TransactionType.income,
];

/// Deletes [item] and offers, for a few seconds, to take that back.
///
/// Deleting only marks the row, so Undo puts it back exactly as it was. The
/// receipt picture is different: once removed from storage it is gone, so it
/// is only removed when the offer has passed without being taken.
///
/// [messenger] is taken before the sheet that asked for this is closed; its
/// own context does not outlive it.
void deleteTransactionWithUndo({
  required ScaffoldMessengerState messenger,
  required TransactionProvider provider,
  required TransactionModel item,
  required String deletedLabel,
  required String undoLabel,
  ReceiptStore receipts = const ReceiptStore(),
}) {
  provider.delete(item.id);
  messenger.hideCurrentSnackBar();
  messenger
      .showSnackBar(
        SnackBar(
          key: const ValueKey<String>('transaction-deleted'),
          duration: const Duration(seconds: 6),
          // Goes away on its own: an Undo left on screen for good would hold
          // on to the receipt for good too.
          persist: false,
          content: Text(deletedLabel),
          action: SnackBarAction(
            label: undoLabel,
            onPressed: () => provider.restore(item),
          ),
        ),
      )
      .closed
      .then((reason) {
        final receipt = item.attachmentPath;
        if (reason != SnackBarClosedReason.action && receipt != null) {
          receipts.remove(receipt);
        }
      });
}

/// Opens the recurring-payment (bill) form. Shared with the dashboard's
/// "Add Payment" action, which is why it lives outside the screen.
Future<void> showAddRecurringPaymentSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    title: context.t('Add Recurring Payment', 'आवर्ती भुक्तानी थप्नुहोस्'),
    builder: (_) => const _RecurringForm(),
  );
}

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  int _tab = 0;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Arriving from a search made elsewhere, the box shows what the list
    // is being narrowed to, so it can be changed or cleared here.
    _search.text = context.read<TransactionProvider>().filter.query;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Back to every transaction: the filters, the type chip and the search.
  void _clearFilters() {
    _search.clear();
    context.read<TransactionProvider>().clearFilters();
  }

  void _add() {
    if (_tab == 0) {
      showGlassSheet<void>(
        context: context,
        title: context.t('Add Transaction', 'कारोबार थप्नुहोस्'),
        builder: (_) => const _TransactionForm(),
      );
    } else {
      showAddRecurringPaymentSheet(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: PageRefresh(
        pageName: 'Payments',
        pageNameNe: 'भुक्तानी',
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: <Widget>[
            PageHeader(
              title: context.t('Payments', 'भुक्तानी'),
              actions: <Widget>[
                HeaderAction(
                  key: const ValueKey<String>('payments-add'),
                  icon: Icons.add_rounded,
                  label: context.t('Add', 'थप्नुहोस्'),
                  onPressed: _add,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedSwitch<int>(
              key: const ValueKey<String>('payments-switch'),
              segments: <SwitchSegment<int>>[
                SwitchSegment<int>(
                  value: 0,
                  icon: Icons.receipt_long_rounded,
                  label: context.t('Recent', 'हालैका'),
                ),
                SwitchSegment<int>(
                  value: 1,
                  icon: Icons.event_repeat_rounded,
                  label: context.t('Recurring', 'आवर्ती'),
                ),
              ],
              selected: _tab,
              onChanged: (value) => setState(() => _tab = value),
            ),
            const SizedBox(height: 16),
            if (_tab == 0) ..._recent(context) else ..._recurring(context),
          ],
        ),
      ),
    );
  }

  /// The list cut into days, when it is in date order. Sorted by amount it
  /// is one run, and each row says its own date instead.
  List<_DaySection> _sections(
    BuildContext context,
    List<TransactionModel> items,
    TransactionSort sort,
  ) {
    if (sort != TransactionSort.dateDesc && sort != TransactionSort.dateAsc) {
      return <_DaySection>[_DaySection(null, items)];
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final sections = <_DaySection>[];
    DateTime? current;
    for (final item in items) {
      final at = item.occurredAt;
      final day = DateTime(at.year, at.month, at.day);
      if (current == null || day != current) {
        current = day;
        sections.add(
          _DaySection(
            day == today
                ? context.t('Today', 'आज')
                : day == yesterday
                ? context.t('Yesterday', 'हिजो')
                : formatDate(day),
            <TransactionModel>[],
          ),
        );
      }
      sections.last.items.add(item);
    }
    return sections;
  }

  List<Widget> _recent(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final glass = context.glass;
    final items = provider.visible;
    final type = provider.filter.type;
    final filterCount = provider.activeFilterCount;

    Widget chip(String label, TransactionType? value) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: type == value,
          onSelected: (_) => provider.setType(value),
        ),
      );
    }

    return <Widget>[
      GlassCard(
        child: Row(
          children: <Widget>[
            Expanded(
              child: _Total(
                label: context.t('Income', 'आम्दानी'),
                value: provider.totalFor(TransactionType.income),
                color: glass.success,
              ),
            ),
            Container(width: 0.5, height: 36, color: glass.hairline),
            const SizedBox(width: 16),
            Expanded(
              child: _Total(
                label: context.t('Expense', 'खर्च'),
                value: provider.totalFor(TransactionType.expense),
                color: glass.danger,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: provider.setSearch,
              decoration: InputDecoration(
                hintText: context.t(
                  'Search transactions',
                  'कारोबार खोज्नुहोस्',
                ),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: filterCount > 0,
            label: Text('$filterCount'),
            child: IconButton.filledTonal(
              key: const ValueKey<String>('payments-filter'),
              tooltip: context.t('Filter', 'फिल्टर'),
              onPressed: () => showTransactionFilterSheet(context),
              icon: const Icon(Icons.tune_rounded),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: <Widget>[
            chip(context.t('All', 'सबै'), null),
            chip(context.t('Expense', 'खर्च'), TransactionType.expense),
            chip(context.t('Income', 'आम्दानी'), TransactionType.income),
            chip(context.t('Transfer', 'ट्रान्सफर'), TransactionType.transfer),
          ],
        ),
      ),
      if (filterCount > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.t(
                    '${provider.totalMatching} found with '
                        '$filterCount filter${filterCount == 1 ? '' : 's'}',
                    '${L10n.neNumber(filterCount)} फिल्टरमा '
                        '${L10n.neNumber(provider.totalMatching)} भेटियो',
                  ),
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: glass.textSecondary),
                ),
              ),
              TextButton(
                key: const ValueKey<String>('payments-clear-filters'),
                onPressed: _clearFilters,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(context.t('Clear filters', 'फिल्टर हटाउनुहोस्')),
              ),
            ],
          ),
        ),
      const SizedBox(height: 16),
      if (items.isEmpty && provider.isFiltered)
        SizedBox(
          height: 300,
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: context.t('Nothing matches', 'केही भेटिएन'),
            message: context.t(
              'No transaction fits this search and these filters.',
              'यो खोज र फिल्टरसँग कुनै कारोबार मिलेन।',
            ),
            actionLabel: context.t('Clear filters', 'फिल्टर हटाउनुहोस्'),
            onAction: _clearFilters,
          ),
        )
      else if (items.isEmpty)
        SizedBox(
          height: 300,
          child: EmptyState(
            icon: Icons.receipt_long_rounded,
            title: context.t('No transactions', 'कारोबार छैन'),
            message: context.t(
              'Add your first income or expense.',
              'आफ्नो पहिलो आम्दानी वा खर्च थप्नुहोस्।',
            ),
            actionLabel: context.t('Add Transaction', 'कारोबार थप्नुहोस्'),
            onAction: _add,
          ),
        )
      else ...<Widget>[
        for (final section in _sections(
          context,
          items,
          provider.filter.sort,
        )) ...<Widget>[
          if (section.label != null) GroupLabel(section.label!),
          GroupedCard(
            children: <Widget>[
              for (final item in section.items)
                _TransactionRow(item: item, showDate: section.label == null),
            ],
          ),
          const SizedBox(height: 18),
        ],
        if (provider.hasMore)
          Center(
            child: GlassButton(
              label: context.t('Load more', 'थप हेर्नुहोस्'),
              onPressed: provider.loadMore,
            ),
          ),
      ],
    ];
  }

  List<Widget> _recurring(BuildContext context) {
    final provider = context.watch<RecurringPaymentProvider>();
    final glass = context.glass;
    final theme = Theme.of(context);
    final items = provider.all;
    final dueCount = provider.dueToday.length;

    if (items.isEmpty) {
      return <Widget>[
        SizedBox(
          height: 360,
          child: EmptyState(
            icon: Icons.event_repeat_rounded,
            title: context.t('No recurring payments', 'आवर्ती भुक्तानी छैन'),
            message: context.t(
              'Track rent, internet, EMI and other repeating bills.',
              'भाडा, इन्टरनेट, EMI र अरू दोहोरिने बिलको हिसाब राख्नुहोस्।',
            ),
            actionLabel: context.t('Add Recurring', 'आवर्ती थप्नुहोस्'),
            onAction: _add,
          ),
        ),
      ];
    }
    // What the repeating bills come to in a month, so the list answers "how
    // much of my month is already spoken for". Paused ones are left out.
    final active = items.where((item) => item.isActive).toList();
    final monthlyOut = active
        .where((item) => item.type == TransactionType.expense)
        .fold<double>(0, (sum, item) => sum + item.monthlyAmount);
    final monthlyIn = active
        .where((item) => item.type == TransactionType.income)
        .fold<double>(0, (sum, item) => sum + item.monthlyAmount);
    return <Widget>[
      if (monthlyOut > 0 || monthlyIn > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            key: const ValueKey<String>('recurring-monthly-total'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.t('Every month, about', 'हरेक महिना, लगभग'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: glass.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  CurrencyFormatter.format(monthlyOut),
                  key: const ValueKey<String>('recurring-monthly-out'),
                  style: theme.textTheme.headlineSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  monthlyIn > 0
                      ? context.t(
                          'goes out, and '
                              '${CurrencyFormatter.format(monthlyIn)} comes '
                              'in. Weekly and yearly ones are averaged.',
                          'जान्छ, र ${CurrencyFormatter.format(monthlyIn)} '
                              'आउँछ। साप्ताहिक र वार्षिकको औसत लिइएको छ।',
                        )
                      : context.t(
                          'goes out on these. Weekly and yearly ones are '
                              'averaged over a month.',
                          'यिनमा जान्छ। साप्ताहिक र वार्षिकको महिनाको औसत '
                              'लिइएको छ।',
                        ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: glass.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      if (dueCount > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 12),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.notifications_active_rounded,
                size: 18,
                color: glass.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.t(
                    '$dueCount payment${dueCount == 1 ? '' : 's'} due',
                    '${L10n.neNumber(dueCount)} भुक्तानी तिर्न बाँकी',
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: glass.warning,
                  ),
                ),
              ),
            ],
          ),
        ),
      GroupedCard(
        children: <Widget>[for (final item in items) _RecurringRow(item: item)],
      ),
    ];
  }
}

/// A day's worth of the list. A null [label] is a run with no heading.
class _DaySection {
  _DaySection(this.label, this.items);

  final String? label;
  final List<TransactionModel> items;
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;

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
        Text(
          CurrencyFormatter.format(value),
          style: theme.textTheme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.item, required this.showDate});

  final TransactionModel item;

  /// False under a day heading, which already says the date.
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final income = item.isIncome;
    final transfer = item.isTransfer;
    // A transfer is neither good nor bad news, so it gets no colour.
    final tint = transfer
        ? glass.textSecondary
        : (income ? glass.success : glass.danger);
    final details = <String>[
      // The title of a transfer already names both wallets.
      transfer ? context.t('Transfer', 'ट्रान्सफर') : item.paymentMethod.label,
      if (showDate) formatDate(item.occurredAt),
      if (item.status == TransactionStatus.pending)
        context.t('Pending', 'बाँकी'),
    ].join(' • ');
    return GroupedRow(
      onTap: () => showGlassSheet<void>(
        context: context,
        title: item.title,
        builder: (_) => _TransactionActions(id: item.id),
      ),
      leading: LeadingTile(
        color: tint,
        icon: transfer
            ? Icons.swap_horiz_rounded
            : (income
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded),
      ),
      title: Text(item.title),
      subtitle: Text(details),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (item.attachmentPath != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                Icons.attach_file_rounded,
                size: 16,
                color: glass.textSecondary,
                semanticLabel: context.t('Has a receipt', 'रसिद छ'),
              ),
            ),
          TrailingAmount(
            text:
                '${transfer ? '' : (income ? '+' : '-')}'
                '${CurrencyFormatter.format(item.amount)}',
            color: transfer ? null : tint,
          ),
        ],
      ),
    );
  }
}

class _TransactionActions extends StatefulWidget {
  const _TransactionActions({required this.id});

  final String id;

  @override
  State<_TransactionActions> createState() => _TransactionActionsState();
}

class _TransactionActionsState extends State<_TransactionActions> {
  bool _uploading = false;

  String get id => widget.id;

  /// Attaches a receipt to a transaction that was saved without one, or
  /// replaces the one it has.
  Future<void> _attachReceipt() async {
    final provider = context.read<TransactionProvider>();
    final bytes = await pickReceiptImage(context);
    if (bytes == null || !mounted) return;
    setState(() => _uploading = true);
    final path = await uploadReceipt(bytes, id);
    if (!mounted) return;
    if (path == null) {
      setState(() => _uploading = false);
      showMessage(
        context,
        context.t(
          'The receipt could not be uploaded. Check your connection and try '
              'again.',
          'रसिद अपलोड हुन सकेन। इन्टरनेट जाँचेर फेरि प्रयास गर्नुहोस्।',
        ),
      );
      return;
    }
    await provider.setAttachment(id, path);
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _removeReceipt(String path) async {
    final provider = context.read<TransactionProvider>();
    final ok = await provider.setAttachment(id, null);
    // Only once the transaction no longer points at it.
    if (ok) await const ReceiptStore().remove(path);
  }

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final provider = context.watch<TransactionProvider>();
    final item = provider.byId(id);
    if (item == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final receipt = item.attachmentPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: Text(
            CurrencyFormatter.format(item.amount),
            style: theme.textTheme.headlineSmall,
          ),
        ),
        if (item.notes != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              item.notes!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: glass.textSecondary,
              ),
            ),
          ),
        const SizedBox(height: 16),
        // The picture being uploaded takes the place the saved one has, at
        // the same size, so the sheet does not move when it arrives.
        if (_uploading)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Center(
              child: Skeleton(
                label: context.t('Uploading the receipt', 'रसिद अपलोड हुँदैछ'),
                child: const SkeletonLoader(
                  width: 120,
                  height: 120,
                  radius: 14,
                ),
              ),
            ),
          )
        else if (receipt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Center(
              child: GestureDetector(
                key: const ValueKey<String>('transaction-receipt'),
                onTap: () => showReceipt(context, receipt),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: PasalItemImage(
                    path: receipt,
                    size: 120,
                    fallback: Container(
                      width: 120,
                      height: 120,
                      color: glass.fill,
                      child: Icon(
                        Icons.receipt_long_outlined,
                        color: glass.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (!_uploading && !item.isTransfer) ...<Widget>[
          if (receipt != null)
            ActionTile(
              icon: Icons.open_in_full_rounded,
              label: context.t('View receipt', 'रसिद हेर्नुहोस्'),
              onTap: () => showReceipt(context, receipt),
            ),
          ActionTile(
            icon: Icons.add_a_photo_outlined,
            label: receipt == null
                ? context.t('Add receipt', 'रसिद थप्नुहोस्')
                : context.t('Replace receipt', 'रसिद बदल्नुहोस्'),
            onTap: _attachReceipt,
          ),
          if (receipt != null)
            ActionTile(
              icon: Icons.hide_image_outlined,
              label: context.t('Remove receipt', 'रसिद हटाउनुहोस्'),
              onTap: () => _removeReceipt(receipt),
            ),
        ],
        ActionTile(
          icon: Icons.copy_rounded,
          label: context.t('Duplicate', 'नक्कल बनाउनुहोस्'),
          onTap: () {
            Navigator.pop(context);
            provider.duplicate(id);
          },
        ),
        ActionTile(
          icon: Icons.delete_outline_rounded,
          label: context.t('Delete', 'मेट्नुहोस्'),
          color: glass.danger,
          onTap: () {
            final messenger = ScaffoldMessenger.of(context);
            final deleted = context.t(
              'Deleted “${item.title}”',
              '“${item.title}” मेटियो',
            );
            final undo = context.t('Undo', 'फिर्ता');
            Navigator.pop(context);
            deleteTransactionWithUndo(
              messenger: messenger,
              provider: provider,
              item: item,
              deletedLabel: deleted,
              undoLabel: undo,
            );
          },
        ),
      ],
    );
  }
}

class _TransactionForm extends StatefulWidget {
  const _TransactionForm();

  @override
  State<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<_TransactionForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  TransactionType _type = TransactionType.expense;
  PaymentMethod _method = PaymentMethod.cash;
  DateTime _date = DateTime.now();
  Uint8List? _receipt;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final amount = parseAmount(_amount.text);
    if (title.isEmpty) {
      showMessage(context, 'Enter a title');
      return;
    }
    if (amount == null || amount <= 0) {
      showMessage(context, 'Enter a valid amount');
      return;
    }
    setState(() => _saving = true);
    final provider = context.read<TransactionProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // The id is chosen here so the receipt can be stored under it first.
    final id = newId();
    final receipt = _receipt;
    final receiptPath = receipt == null
        ? null
        : await uploadReceipt(receipt, id);
    final ok = await provider.create(
      id: id,
      title: title,
      amount: amount,
      type: _type,
      occurredAt: _date,
      paymentMethod: _method,
      notes: blankToNull(_notes.text),
      attachmentPath: receiptPath,
    );
    if (!mounted) return;
    if (ok) {
      context.read<AiInsightProvider>().reactToTransaction(
        isIncome: _type == TransactionType.income,
        amount: amount,
      );
      navigator.pop();
      if (receipt != null && receiptPath == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text(receiptNotUploadedMessage)),
        );
      }
    } else {
      setState(() => _saving = false);
      showMessage(context, provider.errorMessage ?? 'Could not save');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SegmentedSwitch<TransactionType>(
          segments: <SwitchSegment<TransactionType>>[
            for (final type in _formTypes)
              SwitchSegment<TransactionType>(value: type, label: type.label),
          ],
          selected: _type,
          onChanged: (value) => setState(() => _type = value),
        ),
        const FieldLabel('Title'),
        TextField(
          controller: _title,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(kMaxTitleLength),
          ],
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Groceries'),
        ),
        const FieldLabel('Amount'),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0'),
        ),
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
        TextField(
          controller: _notes,
          decoration: const InputDecoration(hintText: 'Notes'),
        ),
        const FieldLabel('Receipt (optional)'),
        ReceiptField(
          value: _receipt,
          onChanged: (bytes) => setState(() => _receipt = bytes),
        ),
        const SizedBox(height: 20),
        PrimaryButton(label: 'Save', onPressed: _save, isLoading: _saving),
      ],
    );
  }
}

class _RecurringRow extends StatelessWidget {
  const _RecurringRow({required this.item});

  final RecurringPayment item;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final theme = Theme.of(context);
    final bs = context.read<NepaliDateService>().toBs(item.nextDate);
    final bsText =
        '${bs.year}-${bs.month.toString().padLeft(2, '0')}-${bs.day.toString().padLeft(2, '0')} BS';
    final due = item.isDue(DateTime.now());
    final income = item.type == TransactionType.income;

    String badge = '';
    Color badgeColor = glass.textSecondary;
    if (!item.isActive) {
      badge = context.t('Paused', 'रोकिएको');
    } else if (due) {
      badge = context.t('Due', 'तिर्ने बेला');
      badgeColor = glass.danger;
    }

    return GroupedRow(
      onTap: () => showGlassSheet<void>(
        context: context,
        title: item.title,
        builder: (_) => _RecurringActions(id: item.id),
      ),
      leading: LeadingTile(
        color: theme.colorScheme.primary,
        icon: Icons.event_repeat_rounded,
      ),
      title: Text(item.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('${item.frequency.label} • ${formatDate(item.nextDate)}'),
          Text(bsText, style: theme.textTheme.labelSmall),
        ],
      ),
      trailing: TrailingAmount(
        text: '${income ? '+' : '-'}${CurrencyFormatter.format(item.amount)}',
        color: income ? glass.success : null,
        caption: badge,
        captionColor: badgeColor,
      ),
    );
  }
}

class _RecurringActions extends StatelessWidget {
  const _RecurringActions({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecurringPaymentProvider>();
    final item = provider.byId(id);
    if (item == null) return const SizedBox.shrink();
    final glass = context.glass;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: Text(
            CurrencyFormatter.format(item.amount),
            style: theme.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'Next: ${formatDate(item.nextDate)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: glass.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (item.isActive) ...<Widget>[
          ActionTile(
            icon: Icons.check_circle_rounded,
            label: 'Mark as paid',
            color: glass.success,
            onTap: () {
              Navigator.pop(context);
              provider.markPaid(id);
            },
          ),
          ActionTile(
            icon: Icons.skip_next_rounded,
            label: 'Skip once',
            onTap: () {
              Navigator.pop(context);
              provider.skipOnce(id);
            },
          ),
        ],
        ActionTile(
          icon: item.isActive
              ? Icons.pause_circle_outline_rounded
              : Icons.play_circle_outline_rounded,
          label: item.isActive ? 'Pause' : 'Resume',
          onTap: () {
            Navigator.pop(context);
            provider.setActive(id, active: !item.isActive);
          },
        ),
        ActionTile(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          color: glass.danger,
          onTap: () {
            Navigator.pop(context);
            provider.delete(id);
          },
        ),
      ],
    );
  }
}

class _RecurringForm extends StatefulWidget {
  const _RecurringForm();

  @override
  State<_RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends State<_RecurringForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _interval = TextEditingController(text: '30');
  final TextEditingController _notes = TextEditingController();
  TransactionType _type = TransactionType.expense;
  RecurringFrequency _frequency = RecurringFrequency.monthly;
  PaymentMethod _method = PaymentMethod.cash;
  DateTime _start = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _interval.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final amount = parseAmount(_amount.text);
    if (title.isEmpty) {
      showMessage(context, 'Enter a title');
      return;
    }
    if (amount == null || amount <= 0) {
      showMessage(context, 'Enter a valid amount');
      return;
    }
    int? interval;
    if (_frequency == RecurringFrequency.custom) {
      interval = int.tryParse(_interval.text.trim());
      if (interval == null || interval < 1) {
        showMessage(context, 'Enter a valid interval in days');
        return;
      }
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    final day = DateTime(_start.year, _start.month, _start.day);
    final template = RecurringPayment(
      id: '',
      title: title,
      amount: amount,
      frequency: _frequency,
      startDate: day,
      nextDate: day,
      createdAt: now,
      updatedAt: now,
      type: _type,
      paymentMethod: _method,
      intervalDays: interval,
      notes: blankToNull(_notes.text),
    );
    final provider = context.read<RecurringPaymentProvider>();
    final navigator = Navigator.of(context);
    final ok = await provider.create(template);
    if (!mounted) return;
    if (ok) {
      navigator.pop();
    } else {
      setState(() => _saving = false);
      showMessage(context, provider.errorMessage ?? 'Could not save');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SegmentedSwitch<TransactionType>(
          segments: <SwitchSegment<TransactionType>>[
            for (final type in _formTypes)
              SwitchSegment<TransactionType>(value: type, label: type.label),
          ],
          selected: _type,
          onChanged: (value) => setState(() => _type = value),
        ),
        const FieldLabel('Title'),
        TextField(
          controller: _title,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(kMaxTitleLength),
          ],
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Rent, Internet'),
        ),
        const FieldLabel('Amount'),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0'),
        ),
        const FieldLabel('Repeats'),
        OptionChips<RecurringFrequency>(
          options: RecurringFrequency.values,
          selected: _frequency,
          labelOf: (f) => f.label,
          onSelected: (f) => setState(() => _frequency = f),
        ),
        if (_frequency == RecurringFrequency.custom) ...<Widget>[
          const FieldLabel('Every how many days?'),
          TextField(
            controller: _interval,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '30'),
          ),
        ],
        const FieldLabel('Payment method'),
        OptionChips<PaymentMethod>(
          options: PaymentMethod.values,
          selected: _method,
          labelOf: (m) => m.label,
          onSelected: (m) => setState(() => _method = m),
        ),
        const FieldLabel('First due date'),
        DateField(
          value: _start,
          onChanged: (date) {
            if (date != null) setState(() => _start = date);
          },
        ),
        const FieldLabel('Notes (optional)'),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(hintText: 'Notes'),
        ),
        const SizedBox(height: 20),
        PrimaryButton(label: 'Save', onPressed: _save, isLoading: _saving),
      ],
    );
  }
}
