import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'biometric_service.dart';

/// App lock: with it on, Kharcha asks for the phone's own fingerprint, face
/// or screen-lock PIN each time it is opened, and again after it has been
/// out of sight for a while.
///
/// It guards what is on this phone, whoever is signed in, so the setting is
/// the phone's and stays through sign-out. It uses the phone's screen lock
/// rather than a PIN of its own: there is nothing new to remember, and
/// nothing stored that could be read off the phone.
class AppLockController extends ChangeNotifier {
  AppLockController({required this._biometric, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final BiometricService _biometric;
  final DateTime Function() _clock;

  static const String _enabledKey = 'app_lock.enabled';

  /// Away for less than this, the app opens again without asking: switching
  /// to another app to copy a number is not leaving.
  static const Duration grace = Duration(seconds: 30);

  bool _ready = false;
  bool _enabled = false;
  bool _locked = false;
  bool _prompting = false;
  DateTime? _leftAt;

  /// False until the setting has been read at start-up.
  bool get isReady => _ready;
  bool get enabled => _enabled;

  /// Whether the app is to be covered until it is unlocked.
  bool get locked => _locked;

  /// Reads the setting. An app that starts with the lock on starts locked.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? false;
    } catch (_) {
      _enabled = false;
    }
    _locked = _enabled;
    _ready = true;
    notifyListeners();
  }

  /// Whether this phone has a screen lock to ask for at all.
  Future<bool> isAvailable() => _biometric.canUseDeviceLock();

  /// Turns the lock on or off. Either way the person has to pass the
  /// phone's lock first: on, so that a lock they cannot open is never set;
  /// off, so that whoever picked up an open phone cannot remove it.
  /// Returns whether the change was made.
  Future<bool> setEnabled(bool value, {required String reason}) async {
    if (value == _enabled) return true;
    if (!await _authenticate(reason)) return false;
    _enabled = value;
    _locked = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value) {
        await prefs.setBool(_enabledKey, true);
      } else {
        await prefs.remove(_enabledKey);
      }
    } catch (_) {
      // Storage unavailable: the choice lasts for this run only.
    }
    notifyListeners();
    return true;
  }

  /// Asks for the phone's lock and uncovers the app when it is passed.
  Future<bool> unlock({required String reason}) async {
    if (!_locked) return true;
    if (!await _authenticate(reason)) return false;
    _locked = false;
    _leftAt = null;
    notifyListeners();
    return true;
  }

  Future<bool> _authenticate(String reason) async {
    if (_prompting) return false;
    _prompting = true;
    try {
      return await _biometric.authenticateDevice(reason: reason);
    } finally {
      _prompting = false;
    }
  }

  /// The app has gone out of sight.
  void onHidden() {
    if (!_enabled) return;
    _leftAt ??= _clock();
  }

  /// The app is back in front. Locks if it was away long enough.
  void onShown() {
    final left = _leftAt;
    _leftAt = null;
    // The phone's own prompt also takes the app out of front for a moment.
    if (!_enabled || _locked || _prompting || left == null) return;
    if (_clock().difference(left) >= grace) {
      _locked = true;
      notifyListeners();
    }
  }
}
