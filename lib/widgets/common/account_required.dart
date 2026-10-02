import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../screens/auth/guest_upgrade_screen.dart';
import 'glass_back_button.dart';
import 'glass_background.dart';
import 'glass_card.dart';
import 'primary_button.dart';

void _openUpgrade(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const GuestUpgradeScreen()));
}

/// Whether the person may use something that needs an account.
///
/// A guest is told, in a sheet from the bottom, what [feature] needs and is
/// offered a way to create an account; the answer is then `false`. Anyone
/// signed in gets `true` straight away.
Future<bool> requireAccount(
  BuildContext context, {
  required String feature,
  required String featureNe,
}) async {
  if (!context.read<AuthProvider>().isGuest) return true;
  final create = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final glass = sheetContext.glass;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: GlassCard(
            radius: 28,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.lock_outline_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        sheetContext.t(
                          'This needs an account',
                          'यसका लागि खाता चाहिन्छ',
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  sheetContext.t(
                    '$feature works with an account. You are exploring as a '
                        'guest, so everything is kept on this phone only.',
                    '$featureNe खातासँग मात्र चल्छ। तपाईं पाहुनाको रूपमा '
                        'हेर्दै हुनुहुन्छ, त्यसैले सबै कुरा यही फोनमा मात्र छ।',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: glass.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                PrimaryButton(
                  key: const ValueKey<String>('account-required-create'),
                  label: sheetContext.t(
                    'Create account or sign in',
                    'खाता बनाउनुहोस् वा साइन इन गर्नुहोस्',
                  ),
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                ),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: Text(sheetContext.t('Not now', 'अहिले होइन')),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  if (create == true && context.mounted) _openUpgrade(context);
  return false;
}

/// What a page that needs an account shows a guest instead of its content:
/// what the page is for, why it is not available, and the way to get it.
class AccountRequiredView extends StatelessWidget {
  const AccountRequiredView({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.cloud_off_rounded,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Navigator.of(context).canPop()
              ? const GlassBackButton()
              : null,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Spacer(),
                GlassCard(
                  radius: 28,
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(icon, size: 40, color: theme.colorScheme.primary),
                      const SizedBox(height: 14),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: glass.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      PrimaryButton(
                        key: const ValueKey<String>('account-required-create'),
                        label: context.t(
                          'Create account or sign in',
                          'खाता बनाउनुहोस् वा साइन इन गर्नुहोस्',
                        ),
                        icon: Icons.arrow_forward_rounded,
                        onPressed: () => _openUpgrade(context),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
