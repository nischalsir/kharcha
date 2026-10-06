import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/currencies.dart';
import '../../core/errors/app_failure.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/app_settings_model.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/push_provider.dart';
import '../../services/account_avatar_cache.dart';
import '../../services/biometric_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/common/sync_status.dart';
import '../../widgets/common/app_lock_gate.dart';
import '../../widgets/common/auth_widgets.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/theme_mode_selector.dart';
import '../../widgets/common/setting_row.dart';
import 'app_permissions_card.dart';
import 'change_password_screen.dart';
import 'privacy_policy_screen.dart';
import 'two_factor_screen.dart';
import '../../widgets/common/page_refresh.dart';
import '../../widgets/common/glass_back_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppSettingsProvider>();
    final theme = Theme.of(context);
    final glass = context.glass;
    final auth = context.watch<AuthProvider>();
    final sync = context.watch<SyncService>();
    final syncDisplay = SyncDisplay.of(sync, guest: auth.isGuest);

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const GlassBackButton(),
          title: Text(
            context.t('Settings', 'सेटिङहरू'),
            style: theme.textTheme.titleLarge,
          ),
        ),
        body: SafeArea(
          top: false,
          child: PageRefresh(
            pageName: 'Settings',
            pageNameNe: 'सेटिङ',
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              children: <Widget>[
                _SectionHeader(title: context.t('Appearance', 'देखावट')),
                const SizedBox(height: 8),
                GlassCard(
                  padding: const EdgeInsets.all(6),
                  child: ThemeModeSelector(
                    mode: provider.settings.themeMode,
                    onChanged: provider.updateThemeMode,
                  ),
                ),
                const SizedBox(height: 24),
                _SectionHeader(title: context.t('Data & Sync', 'डाटा र सिंक')),
                const SizedBox(height: 8),
                // The same tile as every other card. The icon says how the
                // sync stands, and the button at the end is as wide as a
                // switch, so the words under the name keep their room and
                // the card keeps the height of a one-row card.
                GlassCard(
                  key: const ValueKey<String>('settings-sync'),
                  child: SettingRow(
                    icon: syncDisplay.icon,
                    color: syncDisplay == SyncDisplay.localOnly
                        ? const Color(0xFF0A84FF)
                        : syncDisplay.color(context),
                    title: context.t('Sync', 'सिङ्क'),
                    subtitle: syncDisplay.long(
                      context,
                      waiting: sync.waitingCount,
                    ),
                    trailing: syncDisplay == SyncDisplay.localOnly
                        ? null
                        : IconButton.filledTonal(
                            key: const ValueKey<String>('settings-sync-now'),
                            tooltip: context.t(
                              'Sync now',
                              'अहिले सिङ्क गर्नुहोस्',
                            ),
                            onPressed: syncDisplay == SyncDisplay.syncing
                                ? null
                                : () => syncDisplay == SyncDisplay.failed
                                      ? sync.retryFailed()
                                      : sync.refresh(),
                            constraints: const BoxConstraints.tightFor(
                              width: 40,
                              height: 40,
                            ),
                            padding: EdgeInsets.zero,
                            // The theme's tonal fill is the card's own
                            // colour in light mode, which left no button
                            // to see.
                            style: IconButton.styleFrom(
                              backgroundColor: glass.fill,
                              disabledBackgroundColor: glass.fill,
                              foregroundColor: theme.colorScheme.primary,
                            ),
                            icon: syncDisplay == SyncDisplay.syncing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.sync_rounded, size: 20),
                          ),
                    onTap: () => showSyncStatusSheet(context),
                  ),
                ),
                const SizedBox(height: 24),
                _SectionHeader(
                  title: context.t('Preferences', 'प्राथमिकताहरू'),
                ),
                const SizedBox(height: 8),
                GlassCard(
                  child: Column(
                    children: <Widget>[
                      SettingRow(
                        icon: Icons.currency_rupee_rounded,
                        color: const Color(0xFFFF9F0A),
                        title: context.t('Currency', 'मुद्रा'),
                        subtitle: currencyLabel(provider.currency),
                        onTap: () => _pickCurrency(provider),
                      ),
                      const Divider(height: 1),
                      SettingRow(
                        icon: Icons.language_rounded,
                        color: const Color(0xFFBF5AF2),
                        title: context.t('Language', 'भाषा'),
                        subtitle: provider.devanagariDates
                            ? 'नेपाली (Nepali)'
                            : 'English',
                        onTap: () => _pickLanguage(provider),
                      ),
                      const Divider(height: 1),
                      SettingRow(
                        icon: Icons.calendar_today_rounded,
                        color: const Color(0xFF64D2FF),
                        title: context.t('Calendar', 'पात्रो'),
                        subtitle: provider.calendarType == CalendarSystem.ad
                            ? context.t('Gregorian (AD)', 'ग्रेगोरियन (AD)')
                            : context.t(
                                'Bikram Sambat (BS)',
                                'विक्रम संवत् (BS)',
                              ),
                        onTap: () => _pickCalendar(provider),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _SectionHeader(
                  title: context.t(
                    'Permissions & Notifications',
                    'अनुमति र सूचना',
                  ),
                ),
                const SizedBox(height: 8),
                // One card: what the app may use on this phone, then what it
                // may notify about. Every row is the same tile with a switch
                // at the end, so the icons, the text and the switches line
                // up down the card and with the cards around it.
                const GlassCard(
                  child: Column(
                    children: <Widget>[
                      AppPermissionRows(),
                      _NotificationRows(),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _SectionHeader(title: context.t('Security', 'सुरक्षा')),
                const SizedBox(height: 8),
                // One card here too. The app lock guards this phone, whoever
                // is using it; the rows under it belong to an account, and a
                // guest has none to secure.
                GlassCard(
                  child: Column(
                    children: <Widget>[
                      const AppLockRow(),
                      if (!auth.isGuest) ...<Widget>[
                        const Divider(height: 1),
                        _SecurityRows(
                          more: <Widget>[
                            SettingRow(
                              icon: Icons.verified_user_rounded,
                              color: const Color(0xFF30D158),
                              title: context.t(
                                'Two-factor sign-in',
                                'दुई-चरण प्रमाणीकरण',
                              ),
                              subtitle: auth.hasMfaEnabled
                                  ? context.t(
                                      'On: a code is asked at sign-in',
                                      'खुला: साइन इनमा कोड मागिन्छ',
                                    )
                                  : context.t(
                                      'Off: protect your account with an authenticator app',
                                      'बन्द: प्रमाणक एपले खाता सुरक्षित गर्नुहोस्',
                                    ),
                              trailing: Switch(
                                value: auth.hasMfaEnabled,
                                onChanged: _togglingTwoFactor
                                    ? null
                                    : (value) => _toggleTwoFactor(auth, value),
                              ),
                              onTap: () =>
                                  _open(context, const TwoFactorAuthScreen()),
                            ),
                            const Divider(height: 1),
                            SettingRow(
                              icon: Icons.password_rounded,
                              color: const Color(0xFF0A84FF),
                              title: context.t(
                                'Change password',
                                'पासवर्ड परिवर्तन गर्नुहोस्',
                              ),
                              subtitle: context.t(
                                'Update your account password',
                                'तपाईंको खाता पासवर्ड अद्यावधिक गर्नुहोस्',
                              ),
                              onTap: () =>
                                  _open(context, const ChangePasswordScreen()),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Backup, Help and About live on the More page.
                _SectionHeader(title: context.t('Privacy', 'गोपनीयता')),
                const SizedBox(height: 8),
                GlassCard(
                  child: Column(
                    children: <Widget>[
                      SettingRow(
                        icon: Icons.privacy_tip_rounded,
                        color: const Color(0xFF8E8E93),
                        title: context.t('Privacy Policy', 'गोपनीयता नीति'),
                        subtitle: context.t(
                          'View our privacy policy',
                          'हाम्रो गोपनीयता नीति हेर्नुहोस्',
                        ),
                        onTap: () =>
                            _open(context, const PrivacyPolicyScreen()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _SectionHeader(title: context.t('Danger Zone', 'खतरा क्षेत्र')),
                const SizedBox(height: 8),
                GlassCard(
                  child: Column(
                    children: <Widget>[
                      SettingRow(
                        icon: Icons.delete_forever_rounded,
                        color: glass.danger,
                        title: context.t(
                          'Delete All Data',
                          'सबै डाटा मेटाउनुहोस्',
                        ),
                        subtitle: context.t(
                          'Permanently delete all local data',
                          'सबै स्थानीय डाटा स्थायी रूपमा मेटाउनुहोस्',
                        ),
                        onTap: () => _confirmDeleteAll(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _togglingTwoFactor = false;

  /// The authenticator switch. Turning it on opens the setup screen (scan the
  /// QR code, confirm a code); it only reads "on" once setup is finished.
  /// Turning it off removes the authenticator after a confirmation, because
  /// it lowers the account's protection.
  Future<void> _toggleTwoFactor(AuthProvider auth, bool enable) async {
    if (enable) {
      _open(context, const TwoFactorAuthScreen());
      return;
    }
    final factors = auth.verifiedFactors;
    if (factors.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          dialogContext.t(
            'Turn off two-factor sign-in?',
            'दुई-चरण साइन इन बन्द गर्ने?',
          ),
        ),
        content: Text(
          dialogContext.t(
            'Your account will be protected by your password only. You can '
                'turn it back on at any time.',
            'तपाईंको खाता पासवर्डले मात्र सुरक्षित हुनेछ। जुनसुकै बेला फेरि '
                'खोल्न सकिन्छ।',
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
            child: Text(dialogContext.t('Turn off', 'बन्द गर्नुहोस्')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // The server only removes a factor from a session that has had its code.
    // A fingerprint sign-in skips that step, so ask for it now.
    if (auth.mfaStepUpNeeded) {
      final verified = await _confirmAuthenticatorCode(auth);
      if (!verified || !mounted) return;
    }

    setState(() => _togglingTwoFactor = true);
    try {
      for (final factor in factors) {
        await auth.disableFactor(factor.id);
      }
      if (mounted) {
        showMessage(
          context,
          context.t(
            'Two-factor authentication turned off.',
            'दुई-चरण प्रमाणीकरण बन्द गरियो।',
          ),
        );
      }
    } catch (error) {
      if (mounted) showMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _togglingTwoFactor = false);
    }
  }

  /// Asks for the current authenticator code and verifies it. Returns false
  /// when cancelled.
  Future<bool> _confirmAuthenticatorCode(AuthProvider auth) async {
    final controller = TextEditingController();
    String? error;
    bool busy = false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            dialogContext.t('Enter your code', 'आफ्नो कोड लेख्नुहोस्'),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: dialogContext.t(
                'Authentication code',
                'प्रमाणीकरण कोड',
              ),
              hintText: '000000',
              counterText: '',
              errorText: error,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: busy
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: Text(dialogContext.t('Cancel', 'रद्द गर्नुहोस्')),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final code = controller.text.trim();
                      if (code.length != 6) {
                        setDialogState(
                          () => error = dialogContext.t(
                            'Enter the 6-digit code',
                            '६ अंकको कोड लेख्नुहोस्',
                          ),
                        );
                        return;
                      }
                      setDialogState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await auth.verifyMfa(code);
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (err) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          busy = false;
                          error = AppFailure.from(err).message;
                        });
                      }
                    },
              child: Text(dialogContext.t('Verify', 'प्रमाणित गर्नुहोस्')),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _pickCurrency(AppSettingsProvider provider) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const _SheetTitle('Choose currency'),
            for (final option in kCurrencies)
              ListTile(
                title: Text(option.name),
                subtitle: Text('${option.code}  ${option.symbol}'),
                trailing: option.code == provider.currency
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(context, option.code),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await provider.updateCurrency(selected);
    if (mounted) showMessage(context, 'Currency changed to $selected.');
  }

  Future<void> _pickLanguage(AppSettingsProvider provider) async {
    final selected = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _SheetTitle('Choose language'),
            ListTile(
              title: const Text('English'),
              subtitle: const Text('Dates in Gregorian months, English names'),
              trailing: !provider.devanagariDates
                  ? Icon(
                      Icons.check_circle_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              title: const Text('नेपाली (Nepali)'),
              subtitle: const Text('Dates and festivals in Devanagari'),
              trailing: provider.devanagariDates
                  ? Icon(
                      Icons.check_circle_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await provider.updateDevanagariDates(selected);
    if (mounted) {
      showMessage(
        context,
        selected ? 'भाषा नेपालीमा सेट गरियो।' : 'Language set to English.',
      );
    }
  }

  Future<void> _pickCalendar(AppSettingsProvider provider) async {
    final selected = await showModalBottomSheet<CalendarSystem>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _SheetTitle('Choose calendar'),
            for (final system in CalendarSystem.values)
              ListTile(
                title: Text(
                  system == CalendarSystem.bs
                      ? 'Bikram Sambat (BS)'
                      : 'Gregorian (AD)',
                ),
                subtitle: Text(
                  system == CalendarSystem.bs
                      ? 'Nepali calendar used for festivals'
                      : 'Standard international calendar',
                ),
                trailing: system == provider.calendarType
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(context, system),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await provider.updateCalendarType(selected);
    if (mounted) {
      showMessage(
        context,
        selected == CalendarSystem.ad
            ? 'Calendar set to Gregorian (AD).'
            : 'Calendar set to Bikram Sambat (BS).',
      );
    }
  }

  Future<void> _confirmDeleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Data?'),
        content: const Text(
          'This will permanently delete all your transactions, budgets, friends, and settings. This action cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final provider = context.read<AppSettingsProvider>();
    try {
      await provider.resetAllData();
      if (mounted) showMessage(context, 'All local data has been deleted.');
    } catch (error) {
      if (mounted) showMessage(context, 'Could not delete data: $error');
    }
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return Text(
      title,
      style: theme.textTheme.labelMedium?.copyWith(
        color: glass.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// What Kharcha may notify about: the switches that go under the
/// permissions, in the same card.
///
/// These are preferences the server reads, separate from Android's own
/// permission in the row above them, so they can be turned off and on again
/// freely. With no notifications on this build there is nothing to choose.
class _NotificationRows extends StatelessWidget {
  const _NotificationRows();

  Future<void> _toggleAiContent(
    BuildContext context,
    AppSettingsProvider settings,
    NotificationPrefs prefs,
    bool value,
  ) async {
    final on = context.t(
      'Flamey will notify you about important things only.',
      'Flamey ले महत्त्वपूर्ण कुराको मात्र सूचना दिनेछ।',
    );
    final off = context.t(
      'Flamey’s notifications are off.',
      'Flamey का सूचना बन्द छन्।',
    );
    await settings.updateNotificationPrefs(prefs.copyWith(aiContent: value));
    if (!context.mounted) return;
    showMessage(context, value ? on : off);
  }

  @override
  Widget build(BuildContext context) {
    final push = context.watch<PushProvider>();
    if (!push.isReady) return const SizedBox.shrink();
    final settings = context.watch<AppSettingsProvider>();
    final prefs = settings.settings.notifications;

    return Column(
      children: <Widget>[
        const Divider(height: 1),
        SettingSwitchRow(
          key: const ValueKey<String>('notify-flamey'),
          icon: Icons.auto_awesome_rounded,
          color: const Color(0xFF5E5CE6),
          title: context.t(
            'Flamey’s insights & alerts',
            'Flamey का सुझाव र चेतावनी',
          ),
          subtitle: context.t(
            'Only genuinely important things, at most about once a day',
            'मात्र महत्त्वपूर्ण कुरा, दिनमा बढीमा एक पटक',
          ),
          value: prefs.aiContent,
          // The AI job is server-side, so the switch works either way; it
          // simply has nothing to send if the phone is blocking everything.
          onChanged: (value) =>
              _toggleAiContent(context, settings, prefs, value),
        ),
        const Divider(height: 1),
        SettingSwitchRow(
          key: const ValueKey<String>('notify-daily'),
          icon: Icons.wb_twilight_rounded,
          color: const Color(0xFFFF9F0A),
          title: context.t('Daily greetings', 'दैनिक शुभकामना'),
          subtitle: context.t(
            'Good morning at 6, good night at 10, and a few tips from '
                'Flamey in between',
            'बिहान ६ बजे शुभ प्रभात, राति १० बजे शुभ रात्रि, र बीचमा केही '
                'AI सुझाव',
          ),
          value: prefs.dailyBuddy,
          onChanged: (value) => settings.updateNotificationPrefs(
            prefs.copyWith(dailyBuddy: value),
          ),
        ),
      ],
    );
  }
}

/// Biometric sign-in and "remember me" for the account on this phone, as
/// rows for the Security card, with the account's own rows after them.
class _SecurityRows extends StatefulWidget {
  const _SecurityRows({this.more = const <Widget>[]});

  /// The account's own security rows (two-factor, password), shown in the
  /// same card under this phone's.
  final List<Widget> more;

  @override
  State<_SecurityRows> createState() => _SecurityRowsState();
}

class _SecurityRowsState extends State<_SecurityRows> {
  BiometricCapability _capability = BiometricCapability.none;
  bool _biometricEnabled = false;
  bool _rememberMe = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final BiometricService biometric = context.read<BiometricService>();
    final String? email = context.read<AuthProvider>().userEmail;
    final BiometricCapability capability = await biometric.capability();
    // This switch is for the signed-in account only. Another account on the
    // same phone having fingerprint sign-in says nothing about this one.
    final bool enabled = await biometric.isEnabledFor(email);
    final bool remember = await biometric.rememberMe();
    if (!mounted) return;
    setState(() {
      _capability = capability;
      _biometricEnabled = enabled && capability.available;
      _rememberMe = remember;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    if (_busy) return;
    final BiometricService biometric = context.read<BiometricService>();
    final AuthProvider auth = context.read<AuthProvider>();
    final String? email = auth.userEmail;
    if (email == null || email.isEmpty) {
      showMessage(context, 'Create an account to use biometric sign-in.');
      return;
    }

    if (!value) {
      await biometric.disable(email);
      if (!mounted) return;
      unawaited(context.read<AccountAvatarCache>().remove(email));
      setState(() => _biometricEnabled = false);
      showMessage(context, 'Biometric sign-in turned off.');
      return;
    }

    if (!_capability.available) {
      showMessage(
        context,
        'No fingerprint or face is enrolled on this device.',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final bool verified = await biometric.authenticate(
        reason: 'Enable ${_capability.kind.label} sign-in',
      );
      if (!verified) return;

      // The password has to be typed once more before it can be sealed into
      // the keystore, and it is checked against this account only.
      final String? password = await _promptForPassword(email);
      if (password == null) return;

      // Being inside the app means this account has fully signed in here.
      await biometric.enable(email: email, password: password, trusted: true);
      if (!mounted) return;
      setState(() => _biometricEnabled = true);
      showMessage(context, '${_capability.kind.label} sign-in is ready.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks for the signed-in account's password and returns it once the server
  /// has accepted it, or null when cancelled.
  ///
  /// There is no email field on purpose: checking a different email here would
  /// sign that account in underneath the settings screen.
  Future<String?> _promptForPassword(String email) async {
    final AuthProvider auth = context.read<AuthProvider>();
    final TextEditingController passwordController = TextEditingController();
    String? error;
    bool busy = false;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Confirm your password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(email, style: Theme.of(dialogContext).textTheme.bodySmall),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: busy
                  ? null
                  : () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final String password = passwordController.text;
                      if (password.isEmpty) {
                        setDialogState(() => error = 'Enter your password');
                        return;
                      }
                      setDialogState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await auth.verifyCurrentPassword(password);
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(true);
                        }
                      } catch (err) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          busy = false;
                          error = AppFailure.from(err).message;
                        });
                      }
                    },
              child: Text(busy ? 'Verifying…' : 'Enable'),
            ),
          ],
        ),
      ),
    );

    final String password = passwordController.text;
    return confirmed == true ? password : null;
  }

  Future<void> _toggleRememberMe(bool value) async {
    setState(() => _rememberMe = value);
    await context.read<BiometricService>().setRememberMe(value);
    if (!value && mounted) {
      showMessage(context, 'You will be signed out when Kharcha is closed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;

    final biometricOn = _capability.available && !_busy;
    // Every row the same tile: the same icon box, the same text sizes and
    // the same place for the switch or the arrow. The card is the page's.
    return Column(
      children: <Widget>[
        SettingRow(
          icon: _capability.kind.icon,
          color: const Color(0xFF5E5CE6),
          title: _capability.available
              ? '${_capability.kind.label} sign-in'
              : 'Biometric sign-in',
          subtitle: _capability.available
              ? 'Unlock with ${_capability.kind.label.toLowerCase()} instead of a password'
              : 'No fingerprint or face enrolled on this device',
          enabled: biometricOn,
          trailing: Switch(
            value: _biometricEnabled,
            onChanged: biometricOn ? _toggleBiometric : null,
          ),
          onTap: () => _toggleBiometric(!_biometricEnabled),
        ),
        const Divider(height: 1),
        SettingRow(
          icon: Icons.person_pin_circle_rounded,
          color: const Color(0xFFFF9F0A),
          title: 'Remember me',
          subtitle: 'Keep me signed in on this device',
          enabled: !_busy,
          trailing: Switch(
            value: _rememberMe,
            onChanged: _busy ? null : _toggleRememberMe,
          ),
          onTap: () => _toggleRememberMe(!_rememberMe),
        ),
        // One line above each row; the rows are handed over with lines of
        // their own between them, which are left out.
        for (final row in widget.more)
          if (row is! Divider) ...<Widget>[const Divider(height: 1), row],
        SizedBox(
          height: 4,
          child: _busy ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            'Passwords are stored in the device keystore, never in app data.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: glass.textTertiary,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
