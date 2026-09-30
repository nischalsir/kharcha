/// A single turn in the fixed-topic AI finance chat.
class AiChatMessage {
  const AiChatMessage({
    required this.text,
    required this.fromUser,
    required this.sentAt,
    this.pending = false,
    this.failed = false,
  });

  final String text;
  final bool fromUser;
  final DateTime sentAt;
  final bool pending;
  final bool failed;

  AiChatMessage copyWith({bool? pending, bool? failed, String? text}) {
    return AiChatMessage(
      text: text ?? this.text,
      fromUser: fromUser,
      sentAt: sentAt,
      pending: pending ?? this.pending,
      failed: failed ?? this.failed,
    );
  }
}
