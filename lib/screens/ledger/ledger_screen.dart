import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../providers/friend_provider.dart';
import '../friends/friends_screen.dart';
import '../pasal/pasal_screen.dart';

/// Money owed, in one tab: friends on one side, shops on the other.
///
/// Only the screen is shared. Friends and shops are still kept as they
/// always were (their own records, their own pages and their own routes), so
/// nothing that was saved by an older version changes meaning. Both pages
/// stay alive under the switch, so each keeps its search and its place.
class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final overdue = context.select<FriendProvider, int>(
      (friends) => friends.summary().overdueCount,
    );
    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                key: const ValueKey<String>('ledger-switch'),
                segments: <ButtonSegment<int>>[
                  ButtonSegment<int>(
                    value: 0,
                    icon: const Icon(Icons.people_alt_rounded, size: 18),
                    label: Text(
                      overdue > 0
                          ? context.t(
                              'Friends ($overdue)',
                              'साथीहरू (${L10n.neNumber(overdue)})',
                            )
                          : context.t('Friends', 'साथीहरू'),
                    ),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    icon: const Icon(Icons.storefront_rounded, size: 18),
                    label: Text(context.t('Pasal', 'पसल')),
                  ),
                ],
                showSelectedIcon: false,
                selected: <int>{_tab},
                onSelectionChanged: (value) =>
                    setState(() => _tab = value.first),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const <Widget>[FriendsScreen(), PasalScreen()],
            ),
          ),
        ],
      ),
    );
  }
}
