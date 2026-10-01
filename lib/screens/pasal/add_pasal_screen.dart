import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/pasal_model.dart';
import '../../providers/pasal_provider.dart';
import '../../widgets/common/contact_pick_button.dart';
import '../../widgets/common/primary_button.dart';

import 'package:flutter/services.dart';

class AddPasalScreen extends StatefulWidget {
  const AddPasalScreen({super.key, this.existing});

  final Pasal? existing;

  @override
  State<AddPasalScreen> createState() => _AddPasalScreenState();
}

class _AddPasalScreenState extends State<AddPasalScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _owner;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _notes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _owner = TextEditingController(text: existing?.ownerName ?? '');
    _phone = TextEditingController(text: existing?.phone ?? '');
    _address = TextEditingController(text: existing?.address ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _owner.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Saved in one shape, however it was typed or stored in the contact.
    final phone = readPhoneField(_phone.text).number;
    setState(() => _saving = true);
    final provider = context.read<PasalProvider>();
    final existing = widget.existing;
    final ok = existing == null
        ? await provider.createPasal(
            name: _name.text,
            ownerName: _owner.text.trim().isEmpty ? null : _owner.text.trim(),
            phone: phone,
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          )
        : await provider.updatePasal(
            existing.copyWith(
              name: _name.text.trim(),
              ownerName: () =>
                  _owner.text.trim().isEmpty ? null : _owner.text.trim(),
              phone: () => phone,
              address: () =>
                  _address.text.trim().isEmpty ? null : _address.text.trim(),
              notes: () =>
                  _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ),
          );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      final message = provider.errorMessage ?? 'Could not save Pasal.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(isEdit ? 'Edit Pasal' : 'Add Pasal')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: <Widget>[
              TextFormField(
                controller: _name,
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(100),
                ],
                decoration: const InputDecoration(labelText: 'Pasal name'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _owner,
                decoration: const InputDecoration(labelText: 'Owner name'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: phoneInputFormatters(),
                decoration: InputDecoration(
                  labelText: 'Phone',
                  hintText: '98XXXXXXXX or +977 98XXXXXXXX',
                  // Fills the number, and the owner's name when it is
                  // still empty.
                  suffixIcon: ContactPickButton(phone: _phone, name: _owner),
                ),
                validator: (value) => readPhoneField(value ?? '').invalid
                    ? invalidPhoneMessage(context)
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: isEdit ? 'Save Changes' : 'Add Pasal',
                onPressed: _saving ? null : _save,
                isLoading: _saving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
