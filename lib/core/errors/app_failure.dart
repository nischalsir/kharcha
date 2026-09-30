import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

enum FailureKind {
  offline,
  syncFailed,
  database,
  invalidData,
  export,
  notification,
  ai,
  unknown,
}

class AppFailure implements Exception {
  const AppFailure(this.kind, this.message, {this.cause});

  final FailureKind kind;
  final String message;
  final Object? cause;

  bool get isOffline => kind == FailureKind.offline;

  factory AppFailure.from(Object error) {
    if (error is AppFailure) return error;
    if (error is SocketException ||
        error is TimeoutException ||
        error is AuthRetryableFetchException) {
      return AppFailure(
        FailureKind.offline,
        'You are offline. Changes are saved on this device.',
        cause: error,
      );
    }
    if (error is PostgrestException) {
      final code = error.code ?? '';
      if (code.startsWith('22') || code.startsWith('23')) {
        return AppFailure(
          FailureKind.invalidData,
          'Some data was rejected by the server.',
          cause: error,
        );
      }
      return AppFailure(
        FailureKind.database,
        'Database error. Please try again.',
        cause: error,
      );
    }
    if (error is AuthException) {
      return AppFailure(
        FailureKind.syncFailed,
        'Could not sign in to sync.',
        cause: error,
      );
    }
    final name = error.runtimeType.toString();
    if (name.contains('ClientException') || name.contains('SocketException')) {
      return AppFailure(
        FailureKind.offline,
        'You are offline. Changes are saved on this device.',
        cause: error,
      );
    }
    return AppFailure(
      FailureKind.unknown,
      'Something went wrong.',
      cause: error,
    );
  }

  @override
  String toString() => message;
}
