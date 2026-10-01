import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/utils/phone_number.dart';

/// The one contact the user chose.
class PickedContact {
  const PickedContact({required this.number, this.name});

  /// The number, tidied (see [PhoneNumber.normalize]).
  final String number;

  /// The contact's name, when the phone has one for it.
  final String? name;
}

/// Why a contact could not be picked.
class ContactPickFailure implements Exception {
  const ContactPickFailure(this.reason);

  /// `no_app` when the phone has no contacts app, `no_number` when the
  /// chosen contact has no usable number, otherwise `failed`.
  final String reason;

  @override
  String toString() => 'ContactPickFailure($reason)';
}

/// Lets the user choose one phone number from the phone's contacts.
///
/// Android's own contact picker is opened and hands back only the number
/// that was tapped. The app never reads the address book, so it asks for no
/// contacts permission.
class ContactPicker {
  ContactPicker({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.nischalpandey.kharcha/contacts';

  /// The picker the forms use. Replaced in tests.
  static ContactPicker instance = ContactPicker();

  final MethodChannel _channel;

  /// Whether this device has a contact picker to offer.
  bool get supported => !kIsWeb && Platform.isAndroid;

  /// Opens the picker. Null when the user backed out of it; throws
  /// [ContactPickFailure] when a contact could not be read.
  Future<PickedContact?> pickPhone() async {
    Map<Object?, Object?>? picked;
    try {
      picked = await _channel.invokeMapMethod<Object?, Object?>('pickPhone');
    } on PlatformException catch (error) {
      throw ContactPickFailure(error.code == 'no_app' ? 'no_app' : 'failed');
    } on MissingPluginException {
      throw const ContactPickFailure('no_app');
    }
    if (picked == null) return null;
    final number = PhoneNumber.normalize(picked['number'] as String?);
    if (number == null || !PhoneNumber.isValid(number)) {
      throw const ContactPickFailure('no_number');
    }
    final name = (picked['name'] as String?)?.trim();
    return PickedContact(
      number: number,
      name: name == null || name.isEmpty ? null : name,
    );
  }
}
