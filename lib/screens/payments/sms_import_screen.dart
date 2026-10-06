import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/statement_entry.dart';
import '../../services/sms_service.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_button.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/primary_button.dart';
import 'statement_import_screen.dart';
import '../../widgets/common/glass_back_button.dart';

/// Opens the review of payments read from messages. Nothing is saved until
/// the user picks what to import there.
Future<void> openSmsReview(BuildContext context, StatementParseResult result) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => StatementImportScreen(
        initialResult: result,
        label: context.t('Text messages', 'सन्देशहरू'),
      ),
    ),
  );
}

/// Turns bank and wallet payment alerts into transactions: the messages are
/// copied in the phone's messages app and pasted here, then go through the
/// same review a statement does.
///
/// The app does not read the phone's messages itself. That needs Android's
/// SMS permission, which Google Play Protect treats as a mark of a harmful
/// app when it is asked for by one installed from a file, and it kept
/// Kharcha from being installed at all.
class SmsImportScreen extends StatefulWidget {
  const SmsImportScreen({super.key});

  @override
  State<SmsImportScreen> createState() => _SmsImportScreenState();
}

class _SmsImportScreenState extends State<SmsImportScreen> {
  final TextEditingController _text = TextEditingController();

  /// What the last read came to, said under the button.
  String? _message;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Puts what was last copied into the box. The clipboard is only read
  /// here, when this button is tapped.
  Future<void> _pasteCopied() async {
    final nothing = context.t(
      'Nothing is copied yet. Copy a payment message first.',
      'अहिलेसम्म केही कपी गरिएको छैन। पहिले भुक्तानीको सन्देश कपी गर्नुहोस्।',
    );
    final copied = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (!mounted) return;
    if (copied == null || copied.trim().isEmpty) {
      setState(() => _message = nothing);
      return;
    }
    final before = _text.text.trimRight();
    setState(() {
      _message = null;
      // After what is already there, as one more message.
      _text.text = before.isEmpty
          ? copied.trim()
          : '$before\n\n${copied.trim()}';
    });
  }

  Future<void> _read() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(
        () => _message = context.t(
          'Paste a payment message first.',
          'पहिले भुक्तानीको सन्देश टाँस्नुहोस्।',
        ),
      );
      return;
    }
    final result = SmsParser.parseAll(SmsParser.fromPasted(text));
    if (result.entries.isEmpty) {
      setState(
        () => _message = context.t(
          'No payment was found in what you pasted. Paste the whole message, '
              'as the bank sent it.',
          'टाँसेको सन्देशमा कुनै भुक्तानी भेटिएन। बैंकले पठाएकै पूरा सन्देश '
              'टाँस्नुहोस्।',
        ),
      );
      return;
    }
    setState(() => _message = null);
    await openSmsReview(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: const GlassBackButton(),
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            context.t('Import from SMS', 'SMS बाट आयात'),
            style: theme.textTheme.titleLarge,
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: <Widget>[
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.sms_outlined,
                      color: theme.colorScheme.primary,
                      size: 28,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.t(
                        'Your bank, eSewa and Khalti text you when money '
                            'moves. Copy those messages and paste them here, '
                            'and Kharcha turns them into transactions, so you '
                            'do not type them.',
                        'पैसा चल्दा बैंक, eSewa र Khalti ले सन्देश पठाउँछन्। ती '
                            'सन्देश कपी गरेर यहाँ टाँस्नुहोस्, खर्चाले कारोबार '
                            'बनाउँछ, तपाईंले टाइप गर्नुपर्दैन।',
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t(
                        'Kharcha never reads your messages itself and asks '
                            'for no permission. Only what you paste is read, '
                            'on this phone, and nothing is saved until you '
                            'choose what to import.',
                        'खर्चाले तपाईंका सन्देश आफैँ कहिल्यै पढ्दैन र कुनै '
                            'अनुमति माग्दैन। तपाईंले टाँसेको मात्र, यही फोनमा '
                            'पढिन्छ, र तपाईंले छानेपछि मात्र केही सुरक्षित हुन्छ।',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: glass.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              FieldLabel(context.t('Messages', 'सन्देशहरू')),
              TextField(
                key: const ValueKey<String>('sms-paste-field'),
                controller: _text,
                minLines: 6,
                maxLines: 12,
                decoration: InputDecoration(
                  hintText: context.t(
                    'Dear Customer, Your #1234 has been debited by NPR '
                        '500.00 ...',
                    'Dear Customer, Your #1234 has been debited by NPR '
                        '500.00 ...',
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.t(
                  'For more than one, leave an empty line between them.',
                  'एकभन्दा बढी भए बीचमा एउटा खाली लाइन छोड्नुहोस्।',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: glass.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: GlassButton(
                  key: const ValueKey<String>('sms-paste'),
                  label: context.t(
                    'Paste what I copied',
                    'कपी गरेको टाँस्नुहोस्',
                  ),
                  icon: Icons.content_paste_rounded,
                  onPressed: _pasteCopied,
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                key: const ValueKey<String>('sms-paste-read'),
                label: context.t('Find payments', 'भुक्तानी खोज्नुहोस्'),
                icon: Icons.search_rounded,
                onPressed: _read,
              ),
              if (_message != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  key: const ValueKey<String>('sms-message'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: glass.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
