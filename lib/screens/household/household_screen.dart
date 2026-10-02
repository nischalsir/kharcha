import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/household_model.dart';
import '../../models/payment_method.dart';
import '../../models/transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../repositories/household_repository.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_button.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/glass_sheet.dart';
import '../../widgets/common/page_refresh.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/common/account_required.dart';
import '../../widgets/common/glass_back_button.dart';

/// A ledger shared with family or flatmates: everyone in the household sees
/// and adds to the same list of expenses.
class HouseholdScreen extends StatelessWidget {
  const HouseholdScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // A household is shared between accounts on the server; a guest has no
    // account to share with.
    if (context.select<AuthProvider, bool>((auth) => auth.isGuest)) {
      return AccountRequiredView(
        icon: Icons.groups_rounded,
        title: context.t(
          'Household needs an account',
          'घरपरिवारलाई खाता चाहिन्छ',
        ),
        message: context.t(
          'A household ledger is shared with your family through your '
              'account. Create one, or sign in, to start or join a household.',
          'घरपरिवारको खाता तपाईंको खातामार्फत परिवारसँग साझा हुन्छ। घरपरिवार '
              'सुरु गर्न वा जोडिन खाता बनाउनुहोस् वा साइन इन गर्नुहोस्।',
        ),
      );
    }
    final provider = context.watch<HouseholdProvider>();
    final theme = Theme.of(context);
    final household = provider.household;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: const GlassBackButton(),
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            household?.name ?? context.t('Household', 'घरपरिवार'),
            style: theme.textTheme.titleLarge,
          ),
          actions: <Widget>[
            if (household != null) ...<Widget>[
              IconButton(
                key: const ValueKey<String>('household-members'),
                tooltip: context.t('Members', 'सदस्यहरू'),
                onPressed: () => showGlassSheet<void>(
                  context: context,
                  title: context.t('Members', 'सदस्यहरू'),
                  builder: (_) => const _MembersSheet(),
                ),
                icon: const Icon(Icons.group_outlined),
              ),
              IconButton(
                key: const ValueKey<String>('household-add'),
                tooltip: context.t('Add an expense', 'खर्च थप्नुहोस्'),
                onPressed: () => _openEntry(context),
                icon: const Icon(Icons.add_circle_rounded, size: 28),
              ),
            ],
          ],
        ),
        body: SafeArea(
          child: PageRefresh(
            pageName: 'Household',
            pageNameNe: 'घरपरिवार',
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
              children: household == null
                  ? const <Widget>[_Welcome()]
                  : _ledger(context, provider),
            ),
          ),
        ),
      ),
    );
  }

  static void _openEntry(BuildContext context, {HouseholdEntry? existing}) {
    showGlassSheet<void>(
      context: context,
      title: existing == null
          ? context.t('Shared expense', 'साझा खर्च')
          : context.t('Edit expense', 'खर्च सम्पादन'),
      builder: (_) => _EntryForm(existing: existing),
    );
  }

  List<Widget> _ledger(BuildContext context, HouseholdProvider provider) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final entries = provider.monthEntries;
    final shares = provider.monthShares;
    final total = provider.monthTotal;

    return <Widget>[
      GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: context.t('Previous month', 'अघिल्लो महिना'),
              onPressed: provider.previousMonth,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                provider.monthLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: context.t('Next month', 'अर्को महिना'),
              onPressed: provider.nextMonth,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      GlassCard(
        strong: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.t('Spent together', 'सँगै खर्च'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: glass.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              CurrencyFormatter.format(total),
              key: const ValueKey<String>('household-total'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            for (final share in shares)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        share.member.userId == provider.myUserId
                            ? context.t(
                                '${share.member.displayName} (you)',
                                '${share.member.displayName} (तपाईं)',
                              )
                            : share.member.displayName,
                        style: theme.textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      CurrencyFormatter.format(share.paid),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (entries.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: EmptyState(
            icon: Icons.receipt_long_outlined,
            title: context.t('Nothing this month', 'यस महिना केही छैन'),
            message: context.t(
              'Add what the household spends: rent, groceries, the '
                  'electricity bill. Everyone in it sees the same list.',
              'घरको खर्च थप्नुहोस्: भाडा, किराना, बिजुलीको बिल। सबै सदस्यले '
                  'एउटै सूची देख्छन्।',
            ),
            actionLabel: context.t('Add an expense', 'खर्च थप्नुहोस्'),
            onAction: () => _openEntry(context),
          ),
        )
      else
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassCard(
              key: ValueKey<String>('household-entry-${entry.id}'),
              onTap: () => _openEntry(context, existing: entry),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          entry.title,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${provider.nameOf(entry.paidBy) ?? context.t('Former member', 'पुराना सदस्य')}'
                          ' • ${formatDate(entry.occurredAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: glass.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    CurrencyFormatter.format(entry.amount),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
    ];
  }
}

/// Shown to an account in no household: start one, or join with a code.
class _Welcome extends StatelessWidget {
  const _Welcome();

  void _open(BuildContext context, {required bool joining}) {
    showGlassSheet<void>(
      context: context,
      title: joining
          ? context.t('Join a household', 'घरपरिवारमा जोडिनुहोस्')
          : context.t('Start a household', 'घरपरिवार सुरु गर्नुहोस्'),
      builder: (_) => _JoinForm(joining: joining),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: <Widget>[
          Icon(Icons.groups_rounded, size: 48, color: glass.textTertiary),
          const SizedBox(height: 16),
          Text(
            context.t('One book for the household', 'घरका लागि एउटै खाता'),
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              context.t(
                'Family or flatmates add shared expenses to one list and '
                    'see who paid what. Your own transactions stay private.',
                'परिवार वा साथीहरूले साझा खर्च एउटै सूचीमा थप्छन् र कसले कति '
                    'तिर्‍यो हेर्छन्। तपाईंका आफ्नै कारोबार निजी नै रहन्छन्।',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: glass.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            key: const ValueKey<String>('household-create'),
            label: context.t('Start a household', 'घरपरिवार सुरु गर्नुहोस्'),
            onPressed: () => _open(context, joining: false),
            expanded: false,
          ),
          const SizedBox(height: 10),
          GlassButton(
            key: const ValueKey<String>('household-join'),
            label: context.t('Join with a code', 'कोडबाट जोडिनुहोस्'),
            onPressed: () => _open(context, joining: true),
          ),
        ],
      ),
    );
  }
}

class _JoinForm extends StatefulWidget {
  const _JoinForm({required this.joining});

  final bool joining;

  @override
  State<_JoinForm> createState() => _JoinFormState();
}

class _JoinFormState extends State<_JoinForm> {
  final TextEditingController _first = TextEditingController();
  late final TextEditingController _me;

  @override
  void initState() {
    super.initState();
    String? name;
    try {
      name = context.read<AuthProvider>().profileName;
    } on ProviderNotFoundException {
      name = null;
    }
    _me = TextEditingController(text: name?.trim() ?? '');
  }

  @override
  void dispose() {
    _first.dispose();
    _me.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final provider = context.read<HouseholdProvider>();
    final navigator = Navigator.of(context);
    final ok = widget.joining
        ? await provider.join(code: _first.text, displayName: _me.text)
        : await provider.create(name: _first.text, displayName: _me.text);
    if (!mounted) return;
    if (ok) {
      navigator.pop();
    } else {
      showMessage(
        context,
        provider.errorMessage ??
            context.t('Could not do that', 'त्यो गर्न सकिएन'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<HouseholdProvider>().isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(
          widget.joining
              ? context.t('Invite code', 'निम्तो कोड')
              : context.t('Household name', 'घरपरिवारको नाम'),
        ),
        TextField(
          key: const ValueKey<String>('household-first'),
          controller: _first,
          autofocus: true,
          textCapitalization: widget.joining
              ? TextCapitalization.characters
              : TextCapitalization.words,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(
              widget.joining ? 16 : HouseholdRepository.maxNameLength,
            ),
          ],
          decoration: InputDecoration(
            hintText: widget.joining
                ? context.t('From whoever invited you', 'निम्तो दिनेबाट')
                : context.t('e.g. Our home', 'जस्तै हाम्रो घर'),
          ),
        ),
        FieldLabel(context.t('Your name in it', 'यसमा तपाईंको नाम')),
        TextField(
          key: const ValueKey<String>('household-me'),
          controller: _me,
          textCapitalization: TextCapitalization.words,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(HouseholdRepository.maxNameLength),
          ],
          decoration: InputDecoration(
            hintText: context.t('What the others see', 'अरूले देख्ने नाम'),
          ),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: widget.joining
              ? context.t('Join', 'जोडिनुहोस्')
              : context.t('Start', 'सुरु गर्नुहोस्'),
          onPressed: _submit,
          isLoading: busy,
        ),
      ],
    );
  }
}

/// Who is in the household, the code to invite more, and leaving.
class _MembersSheet extends StatelessWidget {
  const _MembersSheet();

  Future<void> _leave(BuildContext context, {HouseholdMember? member}) async {
    final provider = context.read<HouseholdProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.t('Could not do that', 'त्यो गर्न सकिएन');
    final removing = member != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          removing
              ? dialogContext.t(
                  'Remove ${member.displayName}?',
                  '${member.displayName} लाई हटाउने?',
                )
              : dialogContext.t('Leave this household?', 'यो घरपरिवार छोड्ने?'),
        ),
        content: Text(
          removing
              ? dialogContext.t(
                  'They will no longer see this ledger. What they paid for '
                      'stays in it.',
                  'उहाँले यो खाता अब देख्नुहुन्न। उहाँले तिरेको खर्च यसमै '
                      'रहन्छ।',
                )
              : dialogContext.t(
                  'You will no longer see this ledger. What you paid for '
                      'stays in it for the others.',
                  'तपाईंले यो खाता अब देख्नुहुन्न। तपाईंले तिरेको खर्च '
                      'अरूका लागि यसमै रहन्छ।',
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
            child: Text(
              removing
                  ? dialogContext.t('Remove', 'हटाउनुहोस्')
                  : dialogContext.t('Leave', 'छोड्नुहोस्'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await provider.leave(memberId: member?.userId);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(provider.errorMessage ?? failed)),
      );
      return;
    }
    if (!removing) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HouseholdProvider>();
    final household = provider.household;
    if (household == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final glass = context.glass;
    final me = provider.myUserId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            color: glass.fill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.t('Invite code', 'निम्तो कोड'),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: glass.textSecondary,
                        ),
                      ),
                      SelectableText(
                        household.inviteCode,
                        key: const ValueKey<String>('household-code'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.t('Copy', 'प्रतिलिपि'),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: household.inviteCode),
                    );
                    showMessage(context, context.t('Copied', 'प्रतिलिपि भयो'));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 20),
                ),
                IconButton(
                  tooltip: context.t('Share', 'सेयर'),
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text:
                          'Join "${household.name}" on Kharcha with this '
                          'code: ${household.inviteCode}\n'
                          '(More → Household → Join with a code)',
                    ),
                  ),
                  icon: const Icon(Icons.share_rounded, size: 20),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.t(
            'Anyone with this code can join and see the ledger. Share it '
                'only with the people who belong in it.',
            'यो कोड भएको जोसुकै जोडिन र खाता हेर्न सक्छ। यसमा हुनुपर्ने '
                'मान्छेलाई मात्र दिनुहोस्।',
          ),
          style: theme.textTheme.labelSmall?.copyWith(
            color: glass.textTertiary,
          ),
        ),
        const SizedBox(height: 12),
        for (final member in provider.members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primary.withValues(
                alpha: 0.14,
              ),
              child: Text(
                member.displayName.isEmpty
                    ? '?'
                    : member.displayName.substring(0, 1).toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            title: Text(
              member.userId == me
                  ? context.t(
                      '${member.displayName} (you)',
                      '${member.displayName} (तपाईं)',
                    )
                  : member.displayName,
            ),
            subtitle: member.isOwner ? Text(context.t('Owner', 'मालिक')) : null,
            trailing: provider.isOwner && member.userId != me
                ? IconButton(
                    tooltip: context.t('Remove', 'हटाउनुहोस्'),
                    onPressed: provider.isBusy
                        ? null
                        : () => _leave(context, member: member),
                    icon: const Icon(Icons.person_remove_outlined, size: 20),
                  )
                : null,
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const ValueKey<String>('household-leave'),
          onPressed: provider.isBusy ? null : () => _leave(context),
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: Text(context.t('Leave household', 'घरपरिवार छोड्नुहोस्')),
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
        ),
      ],
    );
  }
}

/// Add a shared expense, or edit/delete one.
class _EntryForm extends StatefulWidget {
  const _EntryForm({this.existing});

  final HouseholdEntry? existing;

  @override
  State<_EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<_EntryForm> {
  late final TextEditingController _title = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null ? '' : _plain(widget.existing!.amount),
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.existing?.notes ?? '',
  );
  late DateTime _date = widget.existing?.occurredAt ?? DateTime.now();
  String? _paidBy;
  bool _alsoMine = false;
  bool _saving = false;

  static String _plain(double value) => value.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    final provider = context.read<HouseholdProvider>();
    _paidBy = widget.existing?.paidBy ?? provider.myUserId;
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showMessage(context, context.t('Enter a title', 'शीर्षक लेख्नुहोस्'));
      return;
    }
    final error = validateAmount(_amount.text);
    if (error != null) {
      showMessage(context, error);
      return;
    }
    final paidBy = _paidBy;
    if (paidBy == null || paidBy.isEmpty) {
      showMessage(
        context,
        context.t('Choose who paid', 'कसले तिर्‍यो छान्नुहोस्'),
      );
      return;
    }
    final amount = parseAmount(_amount.text)!;
    setState(() => _saving = true);
    final provider = context.read<HouseholdProvider>();
    final navigator = Navigator.of(context);
    final existing = widget.existing;
    final ok = existing == null
        ? await provider.addEntry(
            title: title,
            amount: amount,
            paidBy: paidBy,
            occurredAt: _date,
            notes: blankToNull(_notes.text),
          )
        : await provider.updateEntry(
            existing.copyWith(
              title: title,
              amount: amount,
              paidBy: paidBy,
              occurredAt: _date,
              notes: () => blankToNull(_notes.text),
            ),
          );
    if (!mounted) return;
    if (!ok) {
      setState(() => _saving = false);
      showMessage(
        context,
        provider.errorMessage ??
            context.t('Could not save', 'सुरक्षित गर्न सकिएन'),
      );
      return;
    }
    if (existing == null && _alsoMine && paidBy == provider.myUserId) {
      await context.read<TransactionProvider>().create(
        title: title,
        amount: amount,
        type: TransactionType.expense,
        occurredAt: _date,
        paymentMethod: PaymentMethod.cash,
        notes: 'Household: ${provider.household?.name ?? ''}'.trim(),
      );
    }
    navigator.pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final provider = context.read<HouseholdProvider>();
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    await provider.deleteEntry(existing.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HouseholdProvider>();
    final members = provider.members;
    final editing = widget.existing != null;
    final mine = _paidBy == provider.myUserId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(context.t('What was it?', 'के थियो?')),
        TextField(
          key: const ValueKey<String>('household-title'),
          controller: _title,
          autofocus: !editing,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(kMaxTitleLength),
          ],
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: context.t('e.g. Groceries, Rent', 'जस्तै किराना, भाडा'),
          ),
        ),
        FieldLabel(context.t('Amount', 'रकम')),
        TextField(
          key: const ValueKey<String>('household-amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0'),
        ),
        FieldLabel(context.t('Who paid?', 'कसले तिर्‍यो?')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final member in members)
              ChoiceChip(
                label: Text(
                  member.userId == provider.myUserId
                      ? context.t('Me', 'म')
                      : member.displayName,
                ),
                selected: _paidBy == member.userId,
                onSelected: (_) => setState(() => _paidBy = member.userId),
              ),
          ],
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
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(500),
          ],
          decoration: InputDecoration(hintText: context.t('Notes', 'टिप्पणी')),
        ),
        if (!editing && mine)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              context.t(
                'Also add it to my own expenses',
                'मेरो आफ्नै खर्चमा पनि थप्नुहोस्',
              ),
            ),
            value: _alsoMine,
            onChanged: (value) => setState(() => _alsoMine = value),
          ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: context.t('Save', 'सुरक्षित गर्नुहोस्'),
          onPressed: _save,
          isLoading: _saving,
        ),
        if (editing) ...<Widget>[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _saving ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(context.t('Delete', 'मेटाउनुहोस्')),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
