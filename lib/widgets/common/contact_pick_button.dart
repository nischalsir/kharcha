import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/utils/phone_number.dart';
import '../../services/contact_picker.dart';
import 'form_helpers.dart';

/// What a phone field lets through while typing: digits (also Nepali ones),
/// one or more `+`, and the spacing people use. It is tidied when saved.
List<TextInputFormatter> phoneInputFormatters() => <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9०-९+\-() .]')),
  LengthLimitingTextInputFormatter(PhoneNumber.maxInputLength),
];

/// The typed number, tidied for saving: null when the field is empty, and
/// `invalid` true when what was typed is not a phone number.
({String? number, bool invalid}) readPhoneField(String text) {
  final number = PhoneNumber.normalize(text);
  if (number == null) {
    // Something was typed, but there was not a digit in it.
    return (number: null, invalid: text.trim().isNotEmpty);
  }
  return (number: number, invalid: !PhoneNumber.isValid(number));
}

/// The message for a phone number that cannot be saved.
String invalidPhoneMessage(BuildContext context) => context.t(
  'Enter a valid phone number, like 9812345678 or +977 9812345678.',
  'मान्य फोन नम्बर लेख्नुहोस्, जस्तै 9812345678 वा +977 9812345678।',
);

/// The contacts icon at the end of a phone field: opens the phone's contact
/// picker and puts the chosen number into [phone].
///
/// When [name] is given and still empty, the contact's name goes there too,
/// so a friend can be added with one tap. Shown only where the device has a
/// contact picker.
class ContactPickButton extends StatefulWidget {
  const ContactPickButton({super.key, required this.phone, this.name});

  final TextEditingController phone;
  final TextEditingController? name;

  @override
  State<ContactPickButton> createState() => _ContactPickButtonState();
}

class _ContactPickButtonState extends State<ContactPickButton> {
  bool _picking = false;

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final contact = await ContactPicker.instance.pickPhone();
      if (contact == null || !mounted) return;
      widget.phone.text = contact.number;
      final name = widget.name;
      if (name != null && name.text.trim().isEmpty && contact.name != null) {
        name.text = contact.name!;
      }
    } on ContactPickFailure catch (failure) {
      if (!mounted) return;
      showMessage(context, switch (failure.reason) {
        'no_number' => context.t(
          'That contact has no phone number.',
          'त्यो सम्पर्कमा फोन नम्बर छैन।',
        ),
        'no_app' => context.t(
          'No contacts app was found on this phone.',
          'यो फोनमा सम्पर्क एप भेटिएन।',
        ),
        _ => context.t(
          'The contact could not be read. Type the number instead.',
          'सम्पर्क पढ्न सकिएन। नम्बर आफैँ लेख्नुहोस्।',
        ),
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ContactPicker.instance.supported) return const SizedBox.shrink();
    return IconButton(
      onPressed: _picking ? null : _pick,
      tooltip: context.t('Choose from contacts', 'सम्पर्कबाट छान्नुहोस्'),
      icon: const Icon(Icons.contacts_rounded),
    );
  }
}
