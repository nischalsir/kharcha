import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/router/route_paths.dart';
import '../models/financial_summary.dart';
import '../models/push_category.dart';
import '../models/push_message.dart';
import 'push_notification_service.dart';

/// Delivers the flame's reaction to a saved transaction as a push
/// notification rather than a bubble on the balance card.
///
/// Sent through the `send-push` Edge Function to the user's own devices, so it
/// is a genuine FCM notification (and reaches their other phones too). If the
/// backend is unreachable - offline, or not deployed yet - it is drawn locally
/// instead, so the reaction is never silently lost.
class ReactionNotifier {
  const ReactionNotifier._();

  /// Stable id: a new reaction replaces the previous local one instead of
  /// stacking a pile of "Logged!" notifications.
  static const int _localId = 0x4b48;

  static Future<void> deliver(AiMood reaction) async {
    final title = '${reaction.emoji} ${reaction.label}';
    if (await _sendViaFcm(title, reaction.message)) return;
    await PushNotificationService.render(
      PushMessage(
        title: title,
        body: reaction.message,
        category: PushCategory.moodReaction.id,
        data: const <String, String>{'route': RoutePaths.home},
      ),
      id: _localId,
    );
  }

  static Future<bool> _sendViaFcm(String title, String body) async {
    if (!Env.hasSupabase) return false;
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) return false;
      final response = await client.functions
          .invoke(
            'send-push',
            body: <String, dynamic>{
              'category': PushCategory.moodReaction.id,
              'title': title,
              'body': body,
              'data': const <String, String>{'route': RoutePaths.home},
            },
          )
          .timeout(const Duration(seconds: 6));
      final data = response.data;
      final sent = data is Map ? data['sent'] : null;
      return sent is num && sent > 0;
    } catch (error) {
      debugPrint('Reaction: FCM send failed, drawing locally ($error)');
      return false;
    }
  }
}
