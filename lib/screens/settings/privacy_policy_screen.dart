import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';

/// Privacy policy. Written to match how Kharcha actually handles data:
/// local-first storage, optional Supabase sync, and AI insights that run
/// server-side on an aggregated summary only.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String contactEmail = 'nischalpandey.dev@gmail.com';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: theme.colorScheme.onSurface,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('Privacy Policy', style: theme.textTheme.titleLarge),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
            children: const <Widget>[
              _Section(
                title: 'Overview',
                body:
                    'Kharcha is built privacy-first. Your financial records are '
                    'stored on your own device. Nothing is sold, rented or '
                    'shared with advertisers, and there are no third-party '
                    'tracking or analytics SDKs in the app.',
              ),
              _Section(
                title: 'What we store',
                body:
                    'Your transactions, budgets, categories, friends, Pasal '
                    'credit and app preferences are saved locally on this '
                    'device so the app works fully offline.',
              ),
              _Section(
                title: 'Cloud sync',
                body:
                    'If cloud sync is enabled, your records are backed up to '
                    'your private Supabase project. Each row is tied to your '
                    'own account and protected by row-level security, so no '
                    'other user can read or change your data. Sync is optional '
                    'and can be turned off at any time.',
              ),
              _Section(
                title: 'Account & profile',
                body:
                    'When you sign in, we store your account email and the '
                    'profile details you choose to add (name, gender, birth '
                    'date, and an optional profile picture). Your picture is '
                    'uploaded to private storage and shared only through '
                    'short-lived signed links.',
              ),
              _Section(
                title: 'AI insights',
                body:
                    'The AI insight and chat features never send your raw '
                    'transactions anywhere. A secure server-side function '
                    'reads only your own records, builds a small aggregated '
                    'summary (totals, top categories, trends) and sends that '
                    'summary to the AI provider to generate a suggestion. '
                    'Passwords, tokens and other users\' data are never sent.',
              ),
              _Section(
                title: 'Security',
                body:
                    'Passwords are handled by Supabase Auth and are never '
                    'stored in plain text. On-device biometric sign-in keeps '
                    'credentials in the device keystore, not in app data.',
              ),
              _Section(
                title: 'Your control',
                body:
                    'You can delete individual records, clear the local cache '
                    'from Settings, or remove your profile picture at any time. '
                    'Deleting your account removes your synced data.',
              ),
              _Section(
                title: 'Children',
                body:
                    'Kharcha is not directed at children under 13 and does not '
                    'knowingly collect their personal information.',
              ),
              _Section(
                title: 'Contact',
                body:
                    'Questions about this policy? Email '
                    '$contactEmail and we will respond as soon as we can.',
              ),
              SizedBox(height: 8),
              _Footer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: glass.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Row(
        children: <Widget>[
          Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Kharcha does not sell your data or show ads.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
