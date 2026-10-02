import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/payment_method.dart';
import '../models/statement_entry.dart';
import '../models/transaction_model.dart';

/// One received text message.
@immutable
class SmsMessage {
  const SmsMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.date,
  });

  final int id;

  /// Who it came from: a sender name such as `LAXMI_ALERT`, a short code, or
  /// a phone number.
  final String sender;
  final String body;
  final DateTime date;

  static SmsMessage? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final body = raw['body'];
    final date = raw['date'];
    if (body is! String || date is! num) return null;
    return SmsMessage(
      id: (raw['id'] as num?)?.toInt() ?? 0,
      sender: (raw['sender'] as String?) ?? '',
      body: body,
      date: DateTime.fromMillisecondsSinceEpoch(date.toInt()),
    );
  }
}

/// Reads the phone's text messages through the native side. Android only;
/// everywhere else there is no permission and nothing to read.
class SmsService {
  SmsService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.nischalpandey.kharcha/sms';

  final MethodChannel _channel;

  Future<bool> hasPermission() => _flag('hasPermission');

  /// Asks Android for permission to read messages. False when it is refused,
  /// or when Android will not ask (see the screen's own advice for that).
  Future<bool> requestPermission() => _flag('requestPermission');

  Future<bool> _flag(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } catch (error) {
      debugPrint('SMS: $method failed ($error)');
      return false;
    }
  }

  /// Messages received after [since], newest first.
  Future<List<SmsMessage>> read({
    required DateTime since,
    int limit = 1000,
  }) async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'read',
        <String, Object>{'since': since.millisecondsSinceEpoch, 'limit': limit},
      );
      return <SmsMessage>[
        for (final item in raw ?? const <Object?>[]) ?SmsMessage.fromMap(item),
      ];
    } on MissingPluginException {
      return const <SmsMessage>[];
    } catch (error) {
      debugPrint('SMS: could not read messages ($error)');
      return const <SmsMessage>[];
    }
  }
}

/// Picks the payment alerts out of text messages and reads each one into a
/// [StatementEntry], the same shape a statement row has, so it goes through
/// the same review before anything is saved.
///
/// A message is only read when it both names an amount of money and says
/// which way it moved. One-time passwords, offers, balance enquiries, failed
/// payments and anything from a person's own number are left out: a message
/// that is merely about money is not a transaction.
class SmsParser {
  const SmsParser._();

  static final RegExp _amount = RegExp(
    r'(?:NPR|NRS|NRs|Rs|INR|रु)\.?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  /// Words before an amount that make it a balance or a limit, not what
  /// moved.
  static final RegExp _notTheAmount = RegExp(
    r'(bal|balance|limit|available|avl|remaining|due)\W*$',
    caseSensitive: false,
  );

  static final RegExp _out = RegExp(
    r'\b(debited|withdrawn|withdrawal|deducted|paid|payment of|purchase|'
    r'spent|sent|transferred to|dr\.)',
    caseSensitive: false,
  );
  static final RegExp _in = RegExp(
    r'\b(credited|deposited|received|loaded|refund(?:ed)?|reversed|cr\.)',
    caseSensitive: false,
  );

  static final RegExp _ignore = RegExp(
    r'\b(otp|one[- ]time|verification code|password|will be|failed|'
    r'declined|unsuccessful|not successful|request(?:ed)? for|offer|'
    r'win |cashback up ?to|apply now)\b',
    caseSensitive: false,
  );

  static final RegExp _remarks = RegExp(
    r'remarks?\s*[:\-]\s*([^\n\r]+)',
    caseSensitive: false,
  );
  static final RegExp _reference = RegExp(
    // A reference has a digit in it, which keeps a following word from
    // being taken for one.
    r'\b(?:txn|transaction|trans|ref|reference)\b\.?\s*(?:id|no|code)?\b\.?'
    r'\s*[:#]?\s*((?=[A-Z\-]*[0-9])[A-Z0-9][A-Z0-9\-]{5,})',
    caseSensitive: false,
  );
  static final RegExp _counterparty = RegExp(
    r'\b(?:to|from|at)\s+([A-Za-z][A-Za-z0-9 .&\-]{2,40}?)'
    r'(?=\s+(?:on|via|for|ref|txn|using|is|has|was)\b|[.,\n]|$)',
    caseSensitive: false,
  );

  /// A bank's signature at the end of a message: `-Laxmi Sunrise`.
  static final RegExp _signature = RegExp(
    r'(?:^|\s)[-–]\s*([A-Za-z][A-Za-z .&]{2,40})\s*$',
  );

  /// A person's phone number, as opposed to a sender name or a short code.
  static bool _isPhoneNumber(String sender) {
    final digits = sender.replaceAll(RegExp(r'[^0-9]'), '');
    return !sender.contains(RegExp(r'[A-Za-z]')) && digits.length >= 7;
  }

  /// The payment a message reports, or null when it reports none.
  static StatementEntry? parse(SmsMessage message) {
    final body = message.body.trim();
    if (body.isEmpty || _isPhoneNumber(message.sender)) return null;
    if (_ignore.hasMatch(body)) return null;

    final out = _out.firstMatch(body);
    final into = _in.firstMatch(body);
    if (out == null && into == null) return null;
    // Whichever is said first is what happened: "debited ... credited to
    // merchant" is money going out.
    final income = out == null || (into != null && into.start < out.start);

    double? amount;
    for (final match in _amount.allMatches(body)) {
      final before = body.substring(0, match.start);
      if (_notTheAmount.hasMatch(before)) continue;
      final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
      if (value != null && value > 0) {
        amount = value;
        break;
      }
    }
    if (amount == null) return null;

    final lower = '${message.sender} $body'.toLowerCase();
    final source = lower.contains('esewa')
        ? StatementSource.esewa
        : lower.contains('khalti')
        ? StatementSource.khalti
        : StatementSource.bank;

    return StatementEntry(
      occurredAt: message.date,
      title: _titleOf(message, body, income: income),
      amount: (amount * 100).round() / 100,
      type: income ? TransactionType.income : TransactionType.expense,
      paymentMethod: source.isWallet ? source.method : _bankMethod(body),
      source: source,
      reference: _reference.firstMatch(body)?.group(1),
    );
  }

  /// A bank alert is a bank payment unless it says it was a card or a QR.
  static PaymentMethod _bankMethod(String body) {
    final guess = StatementEntry.inferMethod(body);
    return guess == PaymentMethod.card || guess == PaymentMethod.qr
        ? guess
        : PaymentMethod.bank;
  }

  static String _titleOf(
    SmsMessage message,
    String body, {
    required bool income,
  }) {
    String tidy(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

    final remark = _remarks.firstMatch(body)?.group(1);
    if (remark != null) {
      // On one line the bank's signature follows the remark.
      final text = tidy(remark.replaceFirst(_signature, ''));
      if (text.isNotEmpty) return _cap(text);
    }
    final party = _counterparty.firstMatch(body)?.group(1);
    if (party != null) {
      final text = tidy(party);
      // "to your account" names nobody.
      if (text.isNotEmpty &&
          !RegExp(
            r'^(your|a/c|ac|account|the)\b',
            caseSensitive: false,
          ).hasMatch(text)) {
        return _cap(text);
      }
    }
    final bank = _signature.firstMatch(body)?.group(1);
    final who = tidy(bank ?? message.sender);
    final what = income ? 'Deposit' : 'Payment';
    return _cap(who.isEmpty ? what : '$who ${what.toLowerCase()}');
  }

  static String _cap(String text) =>
      text.length <= StatementEntry.maxTitleLength
      ? text
      : '${text.substring(0, StatementEntry.maxTitleLength - 1).trimRight()}…';

  /// Every payment alert in [messages], as a statement ready for review,
  /// oldest first like a statement.
  static StatementParseResult parseAll(List<SmsMessage> messages) {
    final entries = <StatementEntry>[
      for (final message in messages) ?parse(message),
    ]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    StatementEntry.assignFingerprints(entries);
    final sources = <StatementSource>{for (final e in entries) e.source};
    return StatementParseResult(
      entries: entries,
      skipped: const <SkippedStatementRow>[],
      source: sources.length == 1 ? sources.first : StatementSource.other,
      kind: 'sms',
      format: 'sms',
    );
  }
}
