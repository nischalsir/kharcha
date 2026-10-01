import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/core/app_info.dart';

void main() {
  test('AppInfo matches pubspec.yaml, so the update check compares the real '
      'installed version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml has no version line');

    expect(AppInfo.version, match!.group(1));
    expect(AppInfo.buildNumber, match.group(2));
  });

  test('a version is shown without a trailing .0', () {
    expect(AppInfo.short('1.1.0'), '1.1');
    expect(AppInfo.short('2.0.0'), '2.0');
    expect(AppInfo.short('1.3.1'), '1.3.1');
    expect(AppInfo.short('1.10.0'), '1.10');
    // Only the last of three numbers is dropped.
    expect(AppInfo.short('1.0'), '1.0');
    expect(AppInfo.short(''), '');
  });
}
