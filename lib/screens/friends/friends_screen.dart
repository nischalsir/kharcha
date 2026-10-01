import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
import '../../widgets/common/primary_button.dart';
import 'friend_detail_screen.dart';

import 'package:flutter/services.dart';

import '../../widgets/common/page_refresh.dart';

Future<void> showAddFriendSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    title: 'Add Friend',
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

    return SafeArea(
      bottom: false,
      child: PageRefresh(
        pageName: 'Friends',
        pageNameNe: 'साथीहरू',
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('Friends', style: theme.textTheme.headlineMedium),
                ),
                IconButton(
                  onPressed: () => showAddFriendSheet(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 28),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GlassCard(
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _Stat(
                          label: 'They owe you',
                          value: summary.othersOweYou,
                          color: glass.success,
                        ),
                      ),
                      Container(width: 1, height: 36, color: glass.border),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _Stat(
                          label: 'You owe',
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
                          '${summary.overdueCount} overdue',
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
            TextField(
              controller: _search,
              onChanged: provider.setQuery,
              decoration: const InputDecoration(
                hintText: 'Search friends',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            if (friends.isEmpty)
              SizedBox(
                height: 320,
                child: EmptyState(
                  icon: Icons.people_outline,
                  title: 'No friends yet',
                  message: 'Add a friend to track money you lend or borrow.',
                  actionLabel: 'Add Friend',
                  onAction: () => showAddFriendSheet(context),
                ),
              )
            else
              for (final friend in friends)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _FriendTile(friend: friend),
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

class _FriendTile extends StatelessWidget {
  const _FriendTile({required this.friend});

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
    Color color;
    if (net > 0.005) {
      caption = 'owes you';
      color = glass.success;
    } else if (net < -0.005) {
      caption = 'you owe';
      color = glass.danger;
    } else {
      caption = 'settled';
      color = glass.textSecondary;
    }

    return GlassCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => FriendDetailScreen(friendId: friend.id),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              friend.name.isEmpty
                  ? '?'
                  : friend.name.substring(0, 1).toUpperCase(),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  friend.name,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (friend.phone != null)
                  Text(
                    friend.phone!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: glass.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                CurrencyFormatter.format(net.abs()),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                caption,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: glass.textSecondary,
                ),
              ),
            ],
          ),
        ],
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
