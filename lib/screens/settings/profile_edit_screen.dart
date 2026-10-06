import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/config/env.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/app_settings_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/app_images.dart';
import '../../widgets/common/account_required.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/glass_back_button.dart';
import '../../widgets/common/primary_button.dart';
import '../auth/guest_upgrade_screen.dart';
import 'avatar_crop_screen.dart';

/// The account's own page: its picture, who it is, and the personal details.
/// Opened from the Profile card at the top of More.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _ageController;
  UserGender? _selectedGender;
  DateTime? _selectedBirthDate;
  int? _selectedAge;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _nameController = TextEditingController(text: auth.profileName);
    _selectedGender = auth.profileGender;
    _selectedBirthDate = auth.profileBirthDate;
    _selectedAge = auth.profileAge;
    _ageController = TextEditingController(text: _selectedAge?.toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final initialDate =
        _selectedBirthDate ?? DateTime(now.year - 25, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme
                .copyWith(primary: Theme.of(context).colorScheme.primary),
          ),
          child: child!,
        );
      },
    );
    if (date != null && mounted) {
      setState(() {
        _selectedBirthDate = date;
        // Auto-calculate age
        _selectedAge = _calculateAge(date);
        _ageController.text = '$_selectedAge';
      });
    }
  }

  int _calculateAge(DateTime birthDate) {
    final now = DateTime.now();
    int age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final allowed = await requireAccount(
      context,
      feature: 'Your profile',
      featureNe: 'तपाईंको प्रोफाइल',
    );
    if (!allowed || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final auth = context.read<AuthProvider>();
      await auth.updateProfile(
        fullName: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        gender: _selectedGender,
        birthDate: _selectedBirthDate,
        age: _selectedAge,
      );
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, 'Profile updated successfully');
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Failed to update profile: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final glass = context.glass;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const GlassBackButton(),
          title: Text(
            context.t('Profile', 'प्रोफाइल'),
            style: theme.textTheme.titleLarge,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _ProfileHeader(),
                  const SizedBox(height: 24),
                  // Name field
                  Text(
                    'Personal Info',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: glass.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassCard(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: buildInputDecoration(
                            context,
                            label: 'Full Name',
                            hint: 'Enter your name',
                            prefixIcon: Icons.person_outline_rounded,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        InkWell(
                          onTap: _pickBirthDate,
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: buildInputDecoration(
                              context,
                              label: 'Birth Date',
                              prefixIcon: Icons.cake_outlined,
                            ),
                            child: Text(
                              _selectedBirthDate != null
                                  ? '${_selectedBirthDate!.day}/${_selectedBirthDate!.month}/${_selectedBirthDate!.year}'
                                  : 'Select birth date',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: _selectedBirthDate != null
                                    ? colorScheme.onSurface
                                    : glass.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        GenderPicker(
                          value: _selectedGender,
                          label: _genderLabel,
                          onChanged: (value) {
                            setState(() => _selectedGender = value);
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _ageController,
                          decoration: buildInputDecoration(
                            context,
                            label: 'Age',
                            hint: 'Auto-calculated from birth date',
                            prefixIcon: Icons.numbers_rounded,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            _selectedAge = int.tryParse(value);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      label: 'Save Changes',
                      onPressed: _isLoading ? null : _save,
                      isLoading: _isLoading,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _genderLabel(UserGender gender) {
    switch (gender) {
      case UserGender.male:
        return 'Male';
      case UserGender.female:
        return 'Female';
      case UserGender.other:
        return 'Other';
      case UserGender.preferNotToSay:
        return 'Prefer not to say';
    }
  }
}

/// Gender as four pills to tap, in a box like the fields around it. There
/// is no menu to open: every choice is in view, and the chosen one is filled.
class GenderPicker extends StatelessWidget {
  const GenderPicker({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final UserGender? value;
  final String Function(UserGender) label;
  final ValueChanged<UserGender?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final glass = context.glass;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.transgender_rounded,
              size: 20,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Text(
              'Gender',
              style: theme.textTheme.labelMedium?.copyWith(
                color: glass.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          key: const ValueKey<String>('gender-picker'),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final gender in UserGender.values)
                _GenderPill(
                  key: ValueKey<String>('gender-${gender.name}'),
                  label: label(gender),
                  selected: gender == value,
                  onTap: () => onChanged(gender == value ? null : gender),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GenderPill extends StatelessWidget {
  const _GenderPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? colorScheme.primary : colorScheme.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (selected) ...<Widget>[
                  Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: colorScheme.onPrimary,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _AvatarAction { camera, gallery, remove }

/// The profile picture, with the way to change or remove it, above the
/// account it belongs to. A guest is offered the way to keep their data.
class _ProfileHeader extends StatefulWidget {
  const _ProfileHeader();

  @override
  State<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<_ProfileHeader> {
  String? _avatarUrl;
  String? _loadedForUser;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reloadIfNeeded();
  }

  void _reloadIfNeeded() {
    final auth = context.read<AuthProvider>();
    final uid = auth.userId;
    if (uid == null || uid == _loadedForUser) return;
    _loadedForUser = uid;
    _avatarUrl = null;
    auth.signedAvatarUrl().then((url) {
      if (mounted && uid == context.read<AuthProvider>().userId) {
        setState(() => _avatarUrl = url);
      }
    });
  }

  Future<void> _onTap() async {
    final auth = context.read<AuthProvider>();
    final allowed = await requireAccount(
      context,
      feature: 'A profile picture',
      featureNe: 'प्रोफाइल तस्बिर',
    );
    if (!allowed || !mounted) return;
    if (!Env.hasSupabase) {
      showMessage(context, 'Backend is not configured.');
      return;
    }
    if (auth.userId == null) {
      showMessage(context, 'Sign in to set a profile picture.');
      return;
    }

    final action = await showModalBottomSheet<_AvatarAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, _AvatarAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, _AvatarAction.gallery),
            ),
            if (_avatarUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Remove photo'),
                onTap: () => Navigator.pop(context, _AvatarAction.remove),
              ),
            ListTile(
              title: const Text('Cancel', textAlign: TextAlign.center),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _AvatarAction.remove:
        await _remove();
      case _AvatarAction.camera:
      case _AvatarAction.gallery:
        await _pick(action);
    }
  }

  Future<void> _pick(_AvatarAction action) async {
    final auth = context.read<AuthProvider>();
    final source = action == _AvatarAction.camera
        ? ImageSource.camera
        : ImageSource.gallery;
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 95,
    );
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final Uint8List? cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        builder: (_) => AvatarCropScreen(imageBytes: bytes),
      ),
    );
    if (cropped == null || cropped.isEmpty || !mounted) return;

    setState(() => _loading = true);
    try {
      await auth.uploadAvatar(cropped, contentType: 'image/png');
      final url = await auth.signedAvatarUrl();
      if (!mounted) return;
      setState(() => _avatarUrl = url);
      showMessage(context, 'Profile picture updated.');
    } catch (_) {
      if (mounted) showMessage(context, 'Could not update your photo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove() async {
    final auth = context.read<AuthProvider>();
    setState(() => _loading = true);
    try {
      await auth.removeAvatar();
      if (mounted) setState(() => _avatarUrl = null);
    } catch (_) {
      if (mounted) showMessage(context, 'Could not remove your photo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final auth = context.watch<AuthProvider>();
    final name = auth.profileName?.trim();
    final account = auth.isGuest
        ? context.t('Guest', 'पाहुना')
        : (auth.userEmail ?? '');

    return Center(
      child: Column(
        children: <Widget>[
          GestureDetector(
            key: const ValueKey<String>('profile-photo'),
            onTap: _loading ? null : _onTap,
            child: _Avatar(url: _avatarUrl, loading: _loading),
          ),
          TextButton(
            onPressed: _loading ? null : _onTap,
            child: Text(context.t('Change photo', 'तस्बिर फेर्नुहोस्')),
          ),
          if (name != null && name.isNotEmpty)
            Text(
              name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (account.isNotEmpty)
            Text(
              account,
              style: theme.textTheme.bodySmall?.copyWith(
                color: glass.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (auth.isGuest) ...<Widget>[
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const GuestUpgradeScreen(),
                ),
              ),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: Text(
                context.t('Save your data', 'डाटा सुरक्षित गर्नुहोस्'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.url, this.loading = false});

  final String? url;
  final bool loading;

  static const double _size = 96;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final image = url == null
        ? null
        : Image(
            image: AppImages.provider(url!),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _placeholder(theme, colorScheme),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  0.2126, 0.7152, 0.0722, 0, 0, //
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0, 0, 0, 1, 0,
                ]),
                child: child,
              );
            },
          );

    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        ClipOval(
          child: SizedBox(
            width: _size,
            height: _size,
            child: image ?? _placeholder(theme, colorScheme),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
              border: Border.all(color: colorScheme.surface, width: 2),
            ),
            padding: const EdgeInsets.all(6),
            child: loading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : Icon(
                    Icons.photo_camera_rounded,
                    size: 14,
                    color: colorScheme.onPrimary,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _placeholder(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.primary, colorScheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.person_rounded, size: 46, color: colorScheme.onPrimary),
    );
  }
}
