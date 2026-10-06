import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../providers/friend_provider.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/segmented_switch.dart';
import '../friends/friends_screen.dart';
import '../pasal/add_pasal_screen.dart';
import '../pasal/pasal_screen.dart';

/// Money owed, in one tab: shops on one side, friends on the other. Shops
/// come first: the shop's book is what is opened most days.
///
/// The page has a heading of its own, as Payments has, with the one button
/// that adds to whichever side is showing.
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: PageHeader(
              title: context.t('Ledger', 'उधारो'),
              actions: <Widget>[
                HeaderAction(
                  key: const ValueKey<String>('ledger-add'),
                  icon: _tab == 0
                      ? Icons.add_rounded
                      : Icons.person_add_alt_1_rounded,
                  label: context.t('Add', 'थप्नुहोस्'),
                  onPressed: () {
                    if (_tab == 0) {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const AddPasalScreen(),
                        ),
                      );
                    } else {
                      showAddFriendSheet(context);
                    }
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SegmentedSwitch<int>(
              key: const ValueKey<String>('ledger-switch'),
              segments: <SwitchSegment<int>>[
                SwitchSegment<int>(
                  value: 0,
                  icon: Icons.storefront_rounded,
                  label: context.t('Pasal', 'पसल'),
                ),
                SwitchSegment<int>(
                  value: 1,
                  icon: Icons.people_alt_rounded,
                  label: overdue > 0
                      ? context.t(
                          'Friends ($overdue)',
                          'साथीहरू (${L10n.neNumber(overdue)})',
                        )
                      : context.t('Friends', 'साथीहरू'),
                ),
              ],
              selected: _tab,
              onChanged: (value) => setState(() => _tab = value),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const <Widget>[PasalScreen(), FriendsScreen()],
            ),
          ),
        ],
      ),
    );
  }
}
