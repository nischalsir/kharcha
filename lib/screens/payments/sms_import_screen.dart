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
import '../../widgets/common/glass_card.dart';
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

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final refused = context.t(
      'Kharcha is not allowed to read messages. If Android did not ask, '
          'open the phone’s Settings → Apps → Kharcha → Permissions → SMS '
          'and allow it. Some phones first need "Allow restricted settings" '
          'from the three-dot menu on that page.',
      'खर्चालाई सन्देश पढ्ने अनुमति छैन। Android ले नसोधेमा फोनको Settings → '
          'Apps → Kharcha → Permissions → SMS मा गएर अनुमति दिनुहोस्। केही '
          'फोनमा त्यस पृष्ठको तीन-थोप्ले मेनुबाट पहिले "Allow restricted settings" '
          'थिच्नुपर्छ।',
    );
    final none = context.t(
      'No payment alerts were found in the last $_days days.',
      'पछिल्ला ${L10n.neNumber(_days)} दिनमा भुक्तानीको सन्देश भेटिएन।',
    );
    if (!await _sms.requestPermission()) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = refused;
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
