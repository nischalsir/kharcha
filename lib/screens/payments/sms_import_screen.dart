import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/statement_entry.dart';
import '../../providers/transaction_provider.dart';
import '../../services/cache_service.dart';
import '../../services/sms_service.dart';
import '../../services/statement_importer.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_button.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/glass_sheet.dart';
import '../../widgets/common/primary_button.dart';
import 'statement_import_screen.dart';
import '../../widgets/common/glass_back_button.dart';

/// Where the choices about reading messages are kept, on this phone only.
class SmsSettings {
  const SmsSettings(this._cache);

  static const String _autoKey = 'sms.auto_check';
  static const String _lastKey = 'sms.last_check';

  final CacheService _cache;

  /// Whether new payment alerts are looked for when the app is opened.
  bool get autoCheck => _cache.readBoolSetting(_autoKey) ?? false;

  Future<void> setAutoCheck(bool value) =>
      _cache.writeBoolSetting(_autoKey, value);

  /// Up to when messages have already been looked at.
  DateTime? get lastCheck {
    final raw = int.tryParse(_cache.readSetting(_lastKey) ?? '');
    return raw == null ? null : DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> setLastCheck(DateTime value) =>
      _cache.writeSetting(_lastKey, '${value.millisecondsSinceEpoch}');
}

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

/// Looks for payment alerts that arrived since the last look, and offers to
/// review them. Does nothing unless the user switched this on and Android
/// still allows reading messages.
Future<void> checkNewSmsPayments(
  BuildContext context, {
  SmsService? service,
}) async {
  final CacheService cache;
  final TransactionProvider transactions;
  try {
    cache = context.read<CacheService>();
    transactions = context.read<TransactionProvider>();
  } on ProviderNotFoundException {
    // A test or a preview built without the app's providers.
    return;
  }
  final settings = SmsSettings(cache);
  if (!settings.autoCheck) return;
  final now = DateTime.now();
  final last = settings.lastCheck;
  // Not on every return to the app; a few minutes apart is plenty.
  if (last != null && now.difference(last) < const Duration(minutes: 5)) {
    return;
  }
  final sms = service ?? SmsService();
  if (!await sms.hasPermission()) return;
  // Never further back than a week: older ones are for a scan the user
  // starts, with the period they choose.
  final earliest = now.subtract(const Duration(days: 7));
  final since = last == null || last.isBefore(earliest) ? earliest : last;
  final messages = await sms.read(since: since);
  await settings.setLastCheck(now);
  if (!context.mounted || messages.isEmpty) return;

  final result = SmsParser.parseAll(messages);
  StatementImporter(transactions: transactions)
      .markAlreadyImported(result.entries);
  final fresh = result.entries.where((e) => !e.alreadyImported).length;
  if (fresh == 0) return;

  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        // Clear of the floating navigation bar.
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        content: Text(
          context.t(
            '$fresh new ${fresh == 1 ? 'payment' : 'payments'} in your '
                'messages',
            'सन्देशमा ${L10n.neNumber(fresh)} नयाँ भुक्तानी',
          ),
        ),
        action: SnackBarAction(
          label: context.t('Review', 'हेर्नुहोस्'),
          onPressed: () {
            if (context.mounted) openSmsReview(context, result);
          },
        ),
      ),
    );
}

/// Finds bank and wallet payment alerts among the phone's text messages and
/// hands them to the same review a statement goes through.
class SmsImportScreen extends StatefulWidget {
  const SmsImportScreen({super.key, this.service});

  /// Replaces the phone's messages in tests.
  final SmsService? service;

  @override
  State<SmsImportScreen> createState() => _SmsImportScreenState();
}

class _SmsImportScreenState extends State<SmsImportScreen> {
  late final SmsService _sms = widget.service ?? SmsService();
  late final SmsSettings _settings = SmsSettings(context.read<CacheService>());

  static const List<int> _periods = <int>[7, 30, 90];

  int _days = 30;
  bool _busy = false;

  /// What the last scan came to, said under the button.
  String? _message;

  /// True once Android has refused the permission, which is when the way
  /// round it is shown.
  bool _blocked = false;

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _message = null;
      _blocked = false;
    });
    final none = context.t(
      'No payment alerts were found in the last $_days days.',
      'पछिल्ला ${L10n.neNumber(_days)} दिनमा भुक्तानीको सन्देश भेटिएन।',
    );
    if (!await _sms.requestPermission()) {
      if (mounted) {
        setState(() {
          _busy = false;
          _blocked = true;
        });
      }
      return;
    }
    final now = DateTime.now();
    final messages = await _sms.read(
      since: now.subtract(Duration(days: _days)),
      limit: 2000,
    );
    await _settings.setLastCheck(now);
    if (!mounted) return;
    final result = SmsParser.parseAll(messages);
    setState(() {
      _busy = false;
      _message = result.entries.isEmpty ? none : null;
    });
    if (result.entries.isEmpty) return;
    await openSmsReview(context, result);
  }

  /// Reads messages the user pasted in, for a phone that will not let the
  /// app read them. They go through the same review as a scan.
  Future<void> _paste() async {
    final text = await showGlassSheet<String>(
      context: context,
      title: context.t('Paste messages', 'सन्देश टाँस्नुहोस्'),
      builder: (_) => const _PasteForm(),
    );
    if (text == null || !mounted) return;
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

  Future<void> _setAuto(bool value) async {
    if (value && !await _sms.requestPermission()) {
      if (mounted) {
        showMessage(
          context,
          context.t(
            'Allow reading messages first.',
            'पहिले सन्देश पढ्ने अनुमति दिनुहोस्।',
          ),
        );
      }
      return;
    }
    await _settings.setAutoCheck(value);
    // Only what arrives from now on is announced.
    if (value) await _settings.setLastCheck(DateTime.now());
    if (mounted) setState(() {});
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
                            'moves. Kharcha can read those alerts and turn '
                            'them into transactions, so you do not type them.',
                        'पैसा चल्दा बैंक, eSewa र Khalti ले सन्देश पठाउँछन्। '
                            'खर्चाले ती सन्देश पढेर कारोबार बनाउँछ, तपाईंले '
                            'टाइप गर्नुपर्दैन।',
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t(
                        'Messages are read on this phone only. One-time '
                            'passwords and personal messages are skipped, and '
                            'nothing is saved until you choose what to import.',
                        'सन्देश यही फोनमा मात्र पढिन्छन्। OTP र व्यक्तिगत '
                            'सन्देश छोडिन्छन्, र तपाईंले छानेपछि मात्र केही '
                            'सुरक्षित हुन्छ।',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: glass.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const FieldLabel('Look back'),
              OptionChips<int>(
                options: _periods,
                selected: _days,
                labelOf: (days) =>
                    context.t('$days days', '${L10n.neNumber(days)} दिन'),
                onSelected: (days) => setState(() => _days = days),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                key: const ValueKey<String>('sms-scan'),
                label: context.t('Scan messages', 'सन्देश खोज्नुहोस्'),
                icon: Icons.search_rounded,
                onPressed: _scan,
                isLoading: _busy,
              ),
              const SizedBox(height: 10),
              Center(
                child: GlassButton(
                  key: const ValueKey<String>('sms-paste'),
                  label: context.t(
                    'Paste messages instead',
                    'बरु सन्देश टाँस्नुहोस्',
                  ),
                  icon: Icons.content_paste_rounded,
                  onPressed: _paste,
                ),
              ),
              if (_blocked) ...<Widget>[
                const SizedBox(height: 16),
                _BlockedCard(onOpenSettings: _sms.openAppSettings),
              ],
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
              const SizedBox(height: 20),
              GlassCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                // The card paints its own background; the tile needs a
                // Material of its own to draw on.
                child: Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile.adaptive(
                    key: const ValueKey<String>('sms-auto'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      context.t(
                        'Check when I open the app',
                        'एप खोल्दा जाँच्नुहोस्',
                      ),
                    ),
                    subtitle: Text(
                      context.t(
                        'Tells you when new payment alerts have arrived, to '
                            'review and import.',
                        'नयाँ भुक्तानीका सन्देश आएमा हेर्न र आयात गर्न '
                            'जानकारी दिन्छ।',
                      ),
                    ),
                    value: _settings.autoCheck,
                    onChanged: _setAuto,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when Android refuses the permission. On Android 13 and later an
/// app installed from a file, not from a store, is not even allowed to ask
/// for SMS until its owner lifts the restriction by hand; this says how.
class _BlockedCard extends StatelessWidget {
  const _BlockedCard({required this.onOpenSettings});

  final Future<bool> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final steps = <String>[
      context.t(
        'Tap "Open app settings" below.',
        'तलको "Open app settings" थिच्नुहोस्।',
      ),
      context.t(
        'Tap the three dots at the top right and choose "Allow restricted '
            'settings", then confirm with your PIN or fingerprint.',
        'माथि दायाँको तीन थोप्ला थिचेर "Allow restricted settings" '
            'छान्नुहोस्, अनि PIN वा फिंगरप्रिन्टले पुष्टि गर्नुहोस्।',
      ),
      context.t(
        'On the same page open Permissions, then SMS, and choose Allow.',
        'त्यही पृष्ठमा Permissions, अनि SMS खोलेर Allow छान्नुहोस्।',
      ),
      context.t(
        'Come back here and tap Scan messages again.',
        'यहाँ फर्केर फेरि "सन्देश खोज्नुहोस्" थिच्नुहोस्।',
      ),
    ];
    return GlassCard(
      key: const ValueKey<String>('sms-blocked'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.shield_outlined, color: glass.warning, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.t(
                    'Android blocked the SMS permission',
                    'Android ले SMS अनुमति रोक्यो',
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.t(
              'Kharcha was installed from a file, not from Google Play, so '
                  'Android does not let it ask for this until you allow it '
                  'yourself. It takes a minute, once:',
              'खर्चा Google Play बाट नभई फाइलबाट इन्स्टल भएकाले तपाईंले आफैँ '
                  'अनुमति नदिएसम्म Android ले यो माग्न दिँदैन। एक पटक, एक '
                  'मिनेट लाग्छ:',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: glass.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          PrimaryButton(
            key: const ValueKey<String>('sms-open-settings'),
            label: context.t('Open app settings', 'एप सेटिङ खोल्नुहोस्'),
            icon: Icons.settings_rounded,
            onPressed: onOpenSettings,
          ),
          const SizedBox(height: 8),
          Text(
            context.t(
              'If "Allow restricted settings" is not in the menu, or you would '
                  'rather not, use "Paste messages instead": copy a bank '
                  'message and paste it here. That needs no permission.',
              '"Allow restricted settings" मेनुमा नभए वा नचाहेमा "बरु सन्देश '
                  'टाँस्नुहोस्" प्रयोग गर्नुहोस्: बैंकको सन्देश कपी गरेर यहाँ '
                  'टाँस्नुहोस्। त्यसलाई कुनै अनुमति चाहिँदैन।',
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: glass.textTertiary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Where bank messages are pasted in by hand.
class _PasteForm extends StatefulWidget {
  const _PasteForm();

  @override
  State<_PasteForm> createState() => _PasteFormState();
}

class _PasteFormState extends State<_PasteForm> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          context.t(
            'Copy a payment message from your bank, eSewa or Khalti and '
                'paste it here. For more than one, leave an empty line '
                'between them.',
            'बैंक, eSewa वा Khalti को भुक्तानी सन्देश कपी गरेर यहाँ '
                'टाँस्नुहोस्। एकभन्दा बढी भए बीचमा एउटा खाली लाइन छोड्नुहोस्।',
          ),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: glass.textSecondary),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey<String>('sms-paste-field'),
          controller: _text,
          autofocus: true,
          minLines: 5,
          maxLines: 10,
          decoration: InputDecoration(
            hintText: context.t(
              'Dear Customer, Your #1234 has been debited by NPR 500.00 ...',
              'Dear Customer, Your #1234 has been debited by NPR 500.00 ...',
            ),
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          key: const ValueKey<String>('sms-paste-read'),
          label: context.t('Read', 'पढ्नुहोस्'),
          onPressed: () {
            final text = _text.text.trim();
            if (text.isEmpty) return;
            Navigator.pop(context, text);
          },
        ),
      ],
    );
  }
}
