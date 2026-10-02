/// The code emailed to confirm a new account, reset a password or change an
/// email address.
///
/// How long it is is the server's decision (its "Email OTP length"), not the
/// app's. This project sends [length] digits. Everything that shows, takes or
/// checks such a code reads the numbers from here, so a change to the server
/// setting is a change to one line.
///
/// Not the code from an authenticator app, which is always six digits.
class EmailCode {
  const EmailCode._();

  /// The number of digits in the code the server emails.
  static const int length = 8;

  /// The shortest code the server can be set to send. A code at least this
  /// long may be submitted, so turning the server setting down never locks
  /// anyone out of an app that has not been updated yet.
  static const int minLength = 6;

  static final RegExp _notDigit = RegExp(r'[^0-9]');

  /// What was typed or pasted, as a code: digits only, no longer than a code
  /// is. A paste of `1234 5678`, `1234-5678` or `Your code: 12345678` all
  /// give `12345678`.
  static String clean(String input) {
    final digits = input.replaceAll(_notDigit, '');
    return digits.length <= length ? digits : digits.substring(0, length);
  }

  /// Whether [input] holds every digit of a code.
  static bool isComplete(String input) => clean(input).length == length;

  /// Whether [input] is enough of a code to be worth sending to the server.
  static bool canSubmit(String input) => clean(input).length >= minLength;
}
