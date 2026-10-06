import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/friend_credit_model.dart';
import '../../models/friend_model.dart';
import '../../providers/friend_provider.dart';
import '../../widgets/common/contact_pick_button.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/glass_sheet.dart';
import '../../widgets/common/grouped_list.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/primary_button.dart';
import 'friend_detail_screen.dart';
import 'split_bill_sheet.dart';

import 'package:flutter/services.dart';

import '../../widgets/common/page_refresh.dart';

Future<void> showAddFriendSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    title: context.t('Add Friend', 'साथी थप्नुहोस्'),
    builder: (_) => const _FriendForm(),
  );
}

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FriendProvider>();
    final summary = provider.summary();
    final friends = provider.friends;
    final glass = context.glass;
    final theme = Theme.of(context);
    // As a page of its own it has a heading and a way back. As one side of
    // the Ledger tab, the Ledger's own heading is above it with the button
    // that adds a friend, so it has neither.
    final standalone = !(ModalRoute.of(context)?.isFirst ?? true);
    final split = HeaderAction(
      key: const ValueKey<String>('friends-split'),
      icon: Icons.call_split_rounded,
      label: context.t('Split a bill', 'बिल बाँड्नुहोस्'),
      prominent: false,
      onPressed: () => showSplitBillSheet(context),
    );

    return SafeArea(
      bottom: false,
      child: PageRefresh(
        // Inside the Ledger tab, it is the Ledger that was refreshed.
        pageName: standalone ? 'Friends' : 'Ledger',
        pageNameNe: standalone ? 'साथीहरू' : 'उधारो',
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: <Widget>[
            if (standalone) ...<Widget>[
              PageHeader(
                title: context.t('Friends', 'साथीहरू'),
                actions: <Widget>[
                  HeaderAction(
                    key: const ValueKey<String>('friends-add'),
                    icon: Icons.person_add_alt_1_rounded,
                    label: context.t('Add', 'थप्नुहोस्'),
                    onPressed: () => showAddFriendSheet(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            GlassCard(
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _Stat(
                          label: context.t('They owe you', 'पाउनुपर्ने'),
                          value: summary.othersOweYou,
                          color: glass.success,
                        ),
                      ),
                      Container(width: 0.5, height: 36, color: glass.hairline),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _Stat(
                          label: context.t('You owe', 'तिर्नुपर्ने'),
                          value: summary.youOwe,
                          color: glass.danger,
                        ),
                      ),
                    ],
                  ),
                  if (summary.overdueCount > 0) ...<Widget>[
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: glass.warning,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          context.t(
                            '${summary.overdueCount} overdue',
                            '${L10n.neNumber(summary.overdueCount)} को म्याद नाघ्यो',
                          ),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: glass.warning,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: provider.setQuery,
                    decoration: InputDecoration(
                      hintText: context.t('Search friends', 'साथी खोज्नुहोस्'),
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Named, not just drawn: a forked arrow on its own says nothing.
            Align(alignment: AlignmentDirectional.centerStart, child: split),
            const SizedBox(height: 8),
            if (friends.isEmpty)
              SizedBox(
                height: 320,
                child: EmptyState(
                  icon: Icons.people_outline,
                  title: context.t('No friends yet', 'अहिलेसम्म साथी छैन'),
                  message: context.t(
                    'Add a friend to track money you lend or borrow.',
                    'सापटी दिएको वा लिएको पैसाको हिसाब राख्न साथी थप्नुहोस्।',
                  ),
                  actionLabel: context.t('Add Friend', 'साथी थप्नुहोस्'),
                  onAction: () => showAddFriendSheet(context),
                ),
              )
            else
              GroupedCard(
                children: <Widget>[
                  for (final friend in friends) _FriendRow(friend: friend),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

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

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.friend});

  final Friend friend;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FriendProvider>();
    final glass = context.glass;
    final theme = Theme.of(context);
    final theyOwe = provider.outstandingFor(
      friend.id,
      FriendCreditDirection.theyOwe,
    );
    final iOwe = provider.outstandingFor(friend.id, FriendCreditDirection.iOwe);
    final net = theyOwe - iOwe;

    String caption;
    Color? color;
    if (net > 0.005) {
      caption = context.t('owes you', 'तपाईंलाई तिर्नुपर्ने');
      color = glass.success;
    } else if (net < -0.005) {
      caption = context.t('you owe', 'तपाईंले तिर्नुपर्ने');
      color = glass.danger;
    } else {
      caption = context.t('settled', 'चुक्ता');
      color = glass.textSecondary;
    }

    return GroupedRow(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => FriendDetailScreen(friendId: friend.id),
        ),
      ),
      leading: LeadingTile.initial(
        color: theme.colorScheme.primary,
        name: friend.name,
      ),
      title: Text(friend.name),
      subtitle: friend.phone == null ? null : Text(friend.phone!),
      trailing: TrailingAmount(
        text: CurrencyFormatter.format(net.abs()),
        color: color,
        caption: caption,
      ),
    );
  }
}

class _FriendForm extends StatefulWidget {
  const _FriendForm();

  @override
  State<_FriendForm> createState() => _FriendFormState();
}

class _FriendFormState extends State<_FriendForm> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMessage(context, 'Enter a name');
      return;
    }
    // Saved in one shape, however it was typed or stored in the contact.
    final phone = readPhoneField(_phone.text);
    if (phone.invalid) {
      showMessage(context, invalidPhoneMessage(context));
      return;
    }
    setState(() => _saving = true);
    final provider = context.read<FriendProvider>();
    final navigator = Navigator.of(context);
    final ok = await provider.createFriend(
      name: name,
      phone: phone.number,
      notes: blankToNull(_notes.text),
    );
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
        const FieldLabel('Name'),
        TextField(
          controller: _name,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(100),
          ],
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Friend name'),
        ),
        const FieldLabel('Phone (optional)'),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: phoneInputFormatters(),
          decoration: InputDecoration(
            hintText: '98XXXXXXXX or +977 98XXXXXXXX',
            // Fills the number, and the name when it is still empty.
            suffixIcon: ContactPickButton(phone: _phone, name: _name),
          ),
        ),
        const FieldLabel('Notes (optional)'),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(hintText: 'Anything to remember'),
        ),
        const SizedBox(height: 20),
        PrimaryButton(label: 'Save', onPressed: _save, isLoading: _saving),
      ],
    );
  }
}
