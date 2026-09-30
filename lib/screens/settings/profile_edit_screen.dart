import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/app_settings_model.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/form_helpers.dart';
import '../../widgets/common/glass_background.dart';
import '../../widgets/common/glass_card.dart';
import '../../widgets/common/primary_button.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
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
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final initialDate = _selectedBirthDate ??
        DateTime(now.year - 25, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Theme.of(context).colorScheme.primary,
            ),
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

    setState(() => _isLoading = true);

    try {
      final auth = context.read<AuthProvider>();
      await auth.updateProfile(
        fullName: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
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
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('Edit Profile', style: theme.textTheme.titleLarge),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name field
                  Text('Personal Info', style: theme.textTheme.labelMedium?.copyWith(
                    color: glass.textSecondary,
                    letterSpacing: 0.5,
                  )),
                  const SizedBox(height: 12),
                  GlassCard(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            hintText: 'Enter your name',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                            border: InputBorder.none,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your name';
                            }
                            return null;
                          },
                        ),
                        const Divider(height: 1),
                        InkWell(
                          onTap: _pickBirthDate,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Birth Date',
                              prefixIcon: Icon(Icons.cake_outlined),
                              border: InputBorder.none,
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
                        const Divider(height: 1),
                        DropdownButtonFormField<UserGender>(
                          initialValue: _selectedGender,
                          decoration: const InputDecoration(
                            labelText: 'Gender',
                            prefixIcon: Icon(Icons.transgender_rounded),
                            border: InputBorder.none,
                          ),
                          items: UserGender.values.map((gender) {
                            return DropdownMenuItem(
                              value: gender,
                              child: Text(_genderLabel(gender)),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() => _selectedGender = value);
                          },
                        ),
                        const Divider(height: 1),
                        TextFormField(
                          initialValue: _selectedAge?.toString(),
                          decoration: const InputDecoration(
                            labelText: 'Age',
                            hintText: 'Auto-calculated from birth date',
                            prefixIcon: Icon(Icons.numbers_rounded),
                            border: InputBorder.none,
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