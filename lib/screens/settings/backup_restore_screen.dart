import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/backup_service.dart';
import '../../services/cache_service.dart';
import '../../services/google_drive_backup_service.dart';
import '../../services/supabase_backup_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/glass_back_button.dart';

/// Backup & restore screen with three transports:
///  * the app's Supabase Storage bucket (per-user cloud folder),
///  * the user's own Google Drive (hidden app folder), and
///  * a `.json` file on the device that can be shared/imported directly.
///
/// The data snapshot/merge logic lives in [BackupService]; this screen only
/// handles transport and presentation.
class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  late final BackupService _backup;
  late final SupabaseBackupService _cloud;

  /// Drive, for the account that is signed in and no other.
  late final GoogleDriveBackupService _drive = GoogleDriveBackupService(
    userId: context.read<AuthProvider>().userId,
  );

  /// Null until known. False when this build carries no Google sign-in
  /// client, in which case Drive is explained instead of offered.
  bool? _driveConfigured;

  bool _busy = false;
  bool _loadingCloud = false;
  List<CloudBackupFile> _cloudFiles = const <CloudBackupFile>[];
  bool _loadingDrive = false;
  List<CloudBackupFile> _driveFiles = const <CloudBackupFile>[];
  String? _lastExportPath;

  @override
  void initState() {
    super.initState();
    _backup = BackupService(
      cache: context.read<CacheService>(),
      sync: context.read<SyncService>(),
    );
    _cloud = SupabaseBackupService();
    if (_cloud.isConfigured) _loadCloud();
    _restoreDrive();
  }

  // --- Google Drive ------------------------------------------------------------

  /// Reconnects silently if this account connected Drive before; never shows
  /// UI.
  Future<void> _restoreDrive() async {
    final configured = await _drive.isConfigured();
    if (!mounted) return;
    setState(() => _driveConfigured = configured);
    if (!configured) return;
    if (await _drive.restore()) await _loadDrive();
    if (mounted) setState(() {});
  }

  Future<void> _connectDrive() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _drive.connect();
      if (!mounted) return;
      showMessage(
        context,
        '${context.t('Connected to Google Drive', 'Google Drive जोडियो')}: '
        '${_drive.accountEmail ?? ''}',
      );
      await _loadDrive();
    } catch (error) {
      if (mounted) showMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnectDrive() async {
    await _drive.disconnect();
    if (!mounted) return;
    setState(() => _driveFiles = const <CloudBackupFile>[]);
    showMessage(
      context,
      context.t(
        'Google Drive disconnected. Your backups stay in Drive.',
        'Google Drive छुटाइयो। ब्याकअपहरू Drive मै रहन्छन्।',
      ),
    );
  }

  Future<void> _loadDrive() async {
    if (!_drive.isConnected) return;
    setState(() => _loadingDrive = true);
    try {
      final files = await _drive.listBackups();
      if (mounted) setState(() => _driveFiles = files);
    } catch (error) {
      if (mounted) showMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _loadingDrive = false);
    }
  }

  Future<void> _uploadDrive() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _drive.upload(_backup.exportToJson());
      if (!mounted) return;
      showMessage(
        context,
        context.t(
          'Backed up to Google Drive.',
          'Google Drive मा ब्याकअप गरियो।',
        ),
      );
      await _loadDrive();
    } catch (error) {
      if (mounted) {
        showMessage(
          context,
          '${context.t('Drive backup failed', 'Drive ब्याकअप असफल भयो')}: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreDriveFile(CloudBackupFile file) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final text = await _drive.download(file);
      if (!mounted) return;
      await _restoreFromText(text, file.name);
    } catch (error) {
      if (mounted) {
        showMessage(
          context,
          '${context.t('Restore failed', 'रिस्टोर असफल भयो')}: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteDriveFile(CloudBackupFile file) async {
    final confirmed = await _confirm(
      title: context.t('Delete backup?', 'ब्याकअप मेटाउनुहुन्छ?'),
      message: context.t(
        'Remove this backup from your Google Drive?',
        'यो ब्याकअप Google Drive बाट हटाउनुहुन्छ?',
      ),
      confirmLabel: context.t('Delete', 'मेटाउनुहोस्'),
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await _drive.delete(file);
      if (!mounted) return;
      setState(
        () => _driveFiles = _driveFiles
            .where((item) => item.path != file.path)
            .toList(),
      );
    } catch (error) {
      if (mounted) {
        showMessage(
          context,
          '${context.t('Delete failed', 'मेटाउन असफल भयो')}: $error',
        );
      }
    }
  }

  Future<void> _loadCloud() async {
    if (!_cloud.isConfigured) return;
    setState(() => _loadingCloud = true);
    try {
      final files = await _cloud.listBackups();
      if (!mounted) return;
      setState(() => _cloudFiles = files);
    } catch (error) {
      if (mounted) showMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _loadingCloud = false);
    }
  }

  Future<void> _uploadCloud() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _cloud.upload(_backup.exportToJson());
      if (!mounted) return;
      showMessage(
        context,
        '${context.t('Backed up to cloud', 'क्लाउडमा ब्याकअप गरियो')}: '
        '${file.name}',
      );
      await _loadCloud();
    } catch (error) {
      if (mounted) {
        showMessage(
          context,
          '${context.t('Cloud backup failed', 'क्लाउड ब्याकअप असफल भयो')}: '
          '$error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreCloud(CloudBackupFile file) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final text = await _cloud.download(file);
      if (!mounted) return;
      await _restoreFromText(text, file.name);
    } catch (error) {
      if (mounted) {
        showMessage(
          context,
          '${context.t('Restore failed', 'रिस्टोर असफल भयो')}: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCloud(CloudBackupFile file) async {
    final confirmed = await _confirm(
      title: context.t('Delete backup?', 'ब्याकअप मेटाउनुहुन्छ?'),
      message: context.t(
        'Remove ${file.name} from cloud storage?',
        '${file.name} क्लाउड स्टोरेजबाट हटाउनुहुन्छ?',
      ),
      confirmLabel: context.t('Delete', 'मेटाउनुहोस्'),
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await _cloud.delete(file);
      if (!mounted) return;
      setState(
        () => _cloudFiles = _cloudFiles
            .where((item) => item.path != file.path)
            .toList(),
      );
      showMessage(context, context.t('Backup deleted.', 'ब्याकअप मेटाइयो।'));
    } catch (error) {
      if (mounted) {
        showMessage(
          context,
          '${context.t('Delete failed', 'मेटाउन असफल भयो')}: $error',
        );
      }
    }
  }

  Future<void> _exportFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _backup.exportToFile();
      if (!mounted) return;
      setState(() => _lastExportPath = file.path);
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'application/json')],
          subject: 'Kharcha backup',
          text: 'My Kharcha data backup',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      if (mounted) {
        showMessage(
          context,
          context.t('Backup file created.', 'ब्याकअप फाइल बनाइयो।'),
        );
      }
    } catch (error) {
      if (mounted) {
        showMessage(
          context,
          '${context.t('Could not create backup file', 'ब्याकअप फाइल बनाउन सकिएन')}: '
          '$error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFile() async {
    if (_busy) return;
    final PlatformFile? picked = await FilePicker.pickFile(
      dialogTitle: context.t(
        'Select a Kharcha backup',
        'खर्चा ब्याकअप छान्नुहोस्',
      ),
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    if (picked == null || !mounted) return;

    final String text;
    try {
      text = utf8.decode(await picked.readAsBytes());
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          context.t('Could not read this file.', 'यो फाइल पढ्न सकिएन।'),
        );
      }
      return;
    }
    setState(() => _busy = true);
    try {
      if (!mounted) return;
      await _restoreFromText(text, picked.name);
    } catch (error) {
      if (mounted) {
        showMessage(
          context,
          '${context.t('Restore failed', 'रिस्टोर असफल भयो')}: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shared restore flow: inspect, confirm, then import.
  Future<void> _restoreFromText(String text, String label) async {
    final BackupSummary summary = _backup.inspect(text);
    if (summary.records == 0) {
      if (mounted) {
        showMessage(
          context,
          context.t(
            'This backup contains no data.',
            'यो ब्याकअपमा कुनै डाटा छैन।',
          ),
        );
      }
      return;
    }
    final confirmed = await _confirm(
      title: context.t(
        'Restore this backup?',
        'यो ब्याकअप रिस्टोर गर्नुहुन्छ?',
      ),
      message:
          '$label\n\n'
          '${context.t('This will import ${summary.records} records '
              '(${summary.tables} kinds of data) and overwrite any records '
              'with the same id. This cannot be undone.', 'यसले ${summary.records} रेकर्ड (${summary.tables} प्रकारका डाटा) '
              'आयात गरी उही id का रेकर्डहरू अधिलेखन गर्नेछ। यो फिर्ता गर्न '
              'सकिँदैन।')}',
      confirmLabel: context.t('Restore', 'रिस्टोर'),
    );
    if (confirmed != true || !mounted) return;
    final result = await _backup.importFromJson(text);
    if (mounted) {
      showMessage(
        context,
        context.t(
          'Restored ${result.records} records.',
          '${result.records} रेकर्ड रिस्टोर गरियो।',
        ),
      );
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t('Cancel', 'रद्द गर्नुहोस्')),
          ),
          destructive
              ? TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: Text(confirmLabel),
                )
              : FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(confirmLabel),
                ),
        ],
      ),
    );
  }

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
          leading: const GlassBackButton(),
          title: Text(
            context.t('Backup & Restore', 'ब्याकअप र रिस्टोर'),
            style: theme.textTheme.titleLarge,
          ),
          actions: <Widget>[
            if (_cloud.isConfigured)
              IconButton(
                tooltip: context.t('Refresh', 'रिफ्रेस'),
                onPressed: _loadingCloud ? null : _loadCloud,
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
            children: <Widget>[
              _SectionLabel(context.t('Cloud backup', 'क्लाउड ब्याकअप')),
              const SizedBox(height: 8),
              if (!_cloud.isConfigured)
                GlassCard(
                  child: Text(
                    context.t(
                      'Cloud backup needs the cloud backend, which is not '
                          'configured in this build.',
                      'क्लाउड ब्याकअपका लागि ब्याकएन्ड चाहिन्छ, जुन यो '
                          'बिल्डमा कन्फिगर गरिएको छैन।',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: glass.textSecondary,
                    ),
                  ),
                )
              else ...<Widget>[
                _ActionCard(
                  icon: Icons.cloud_upload_rounded,
                  color: const Color(0xFF0A84FF),
                  title: context.t(
                    'Back up to cloud',
                    'क्लाउडमा ब्याकअप गर्नुहोस्',
                  ),
                  subtitle: context.t(
                    'Upload a fresh backup to your secure cloud storage',
                    'तपाईंको cloud स्टोरेजमा नयाँ ब्याकअप अपलोड गर्नुहोस्',
                  ),
                  enabled: !_busy,
                  onTap: _uploadCloud,
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Text(
                      context.t('Cloud backups', 'क्लाउड ब्याकअपहरू'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (_loadingCloud)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_cloudFiles.isEmpty && !_loadingCloud)
                  GlassCard(
                    child: Text(
                      context.t(
                        'No cloud backups yet.',
                        'अहिलेसम्म कुनै क्लाउड ब्याकअप छैन।',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: glass.textSecondary,
                      ),
                    ),
                  )
                else
                  for (final file in _cloudFiles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _BackupTile(
                        title: _formatDate(file.updatedAt),
                        subtitle: _formatSize(file.size),
                        icon: Icons.cloud_done_rounded,
                        busy: _busy,
                        onRestore: () => _restoreCloud(file),
                        onDelete: () => _deleteCloud(file),
                      ),
                    ),
              ],
              const SizedBox(height: 26),
              const _SectionLabel('Google Drive'),
              const SizedBox(height: 8),
              if (_driveConfigured == false)
                GlassCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.info_outline_rounded,
                        size: 20,
                        color: glass.warning,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.t(
                            'Google Drive backup is not available in this '
                                'build yet. Kharcha has not been registered '
                                'for Google sign-in, which Drive needs. Cloud '
                                'backup and backup files work as usual.',
                            'यो संस्करणमा Google Drive ब्याकअप अझै उपलब्ध '
                                'छैन। Drive लाई चाहिने Google साइन इनका लागि '
                                'खर्चा दर्ता भएको छैन। क्लाउड ब्याकअप र फाइल '
                                'ब्याकअप सधैंझैं चल्छन्।',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: glass.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (!_drive.isConnected)
                _ActionCard(
                  icon: Icons.add_to_drive_rounded,
                  color: const Color(0xFF34A853),
                  title: context.t(
                    'Connect Google Drive',
                    'Google Drive जोड्नुहोस्',
                  ),
                  subtitle: context.t(
                    'Keep backups in your own Drive. Kharcha only sees its '
                        'own backup files.',
                    'आफ्नै Drive मा ब्याकअप राख्नुहोस्। खर्चाले आफ्नै ब्याकअप '
                        'फाइल मात्र देख्छ।',
                  ),
                  enabled: !_busy && _driveConfigured == true,
                  onTap: _connectDrive,
                )
              else ...<Widget>[
                _ActionCard(
                  icon: Icons.backup_rounded,
                  color: const Color(0xFF34A853),
                  title: context.t(
                    'Back up to Google Drive',
                    'Google Drive मा ब्याकअप',
                  ),
                  subtitle: _drive.accountEmail ?? '',
                  enabled: !_busy,
                  onTap: _uploadDrive,
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Text(
                      context.t('Drive backups', 'Drive ब्याकअपहरू'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (_loadingDrive)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      TextButton(
                        onPressed: _busy ? null : _disconnectDrive,
                        child: Text(context.t('Disconnect', 'छुटाउनुहोस्')),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_driveFiles.isEmpty && !_loadingDrive)
                  GlassCard(
                    child: Text(
                      context.t(
                        'No Drive backups yet.',
                        'अहिलेसम्म कुनै Drive ब्याकअप छैन।',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: glass.textSecondary,
                      ),
                    ),
                  )
                else
                  for (final file in _driveFiles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _BackupTile(
                        title: _formatDate(file.updatedAt),
                        subtitle: _formatSize(file.size),
                        icon: Icons.add_to_drive_rounded,
                        busy: _busy,
                        onRestore: () => _restoreDriveFile(file),
                        onDelete: () => _deleteDriveFile(file),
                      ),
                    ),
              ],
              const SizedBox(height: 26),
              _SectionLabel(context.t('Device file', 'यन्त्र फाइल')),
              const SizedBox(height: 8),
              _ActionCard(
                icon: Icons.upload_file_rounded,
                color: const Color(0xFF30D158),
                title: context.t('Export to file', 'फाइलमा निर्यात गर्नुहोस्'),
                subtitle: context.t(
                  'Save a .json file and share it anywhere',
                  '.json फाइल सुरक्षित गरी जहाँ पनि साझा गर्नुहोस्',
                ),
                enabled: !_busy,
                onTap: _exportFile,
              ),
              const SizedBox(height: 10),
              _ActionCard(
                icon: Icons.restore_rounded,
                color: const Color(0xFFFF9F0A),
                title: context.t('Import from file', 'फाइलबाट आयात गर्नुहोस्'),
                subtitle: context.t(
                  'Restore from a previously exported .json file',
                  'पहिले निर्यात गरिएको .json फाइलबाट रिस्टोर गर्नुहोस्',
                ),
                enabled: !_busy,
                onTap: _importFile,
              ),
              if (_lastExportPath != null) ...<Widget>[
                const SizedBox(height: 10),
                GlassCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF30D158),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${context.t('Last file saved to:', 'अन्तिम फाइल यहाँ सुरक्षित गरियो:')}\n'
                          '$_lastExportPath',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: glass.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_busy) ...<Widget>[
                const SizedBox(height: 22),
                const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return 'Kharcha backup';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: glass.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GlassCard(
        onTap: enabled ? onTap : null,
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: theme.textTheme.titleMedium),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: glass.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: glass.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _BackupTile extends StatelessWidget {
  const _BackupTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.busy,
    required this.onRestore,
    required this.onDelete,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF30D158).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: const Color(0xFF30D158), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleSmall),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: glass.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: busy ? null : onRestore,
            child: const Text('Restore'),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: busy ? null : onDelete,
            icon: Icon(Icons.delete_outline_rounded, color: glass.textTertiary),
          ),
        ],
      ),
    );
  }
}
