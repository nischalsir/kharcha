import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/category_model.dart';
import '../models/transaction_model.dart';

/// Why nothing was heard.
enum VoiceProblem {
  /// The phone has no speech recogniser to ask.
  unavailable,

  /// It could not be started or gave nothing back.
  failed,
}

/// What listening came to: the words, nothing (the person backed out), or
/// the reason it could not listen.
class VoiceResult {
  const VoiceResult.heard(String this.words) : problem = null;
  const VoiceResult.cancelled() : words = null, problem = null;
  const VoiceResult.problem(VoiceProblem this.problem) : words = null;

  final String? words;
  final VoiceProblem? problem;
}

/// Listens through the phone's own speech recogniser.
///
/// The recogniser is the phone's, opened as its own small window: it does
/// the recording, so Kharcha itself never holds the microphone and asks for
/// no permission to use it.
class VoiceInput {
  VoiceInput({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.nischalpandey.kharcha/voice';

  final MethodChannel _channel;

  /// Opens the recogniser with [prompt] and returns what was said.
  Future<VoiceResult> listen({required String prompt, String? language}) async {
    try {
      final heard = await _channel.invokeMethod<String>(
        'listen',
        <String, dynamic>{'prompt': prompt, 'language': ?language},
      );
      if (heard == null || heard.trim().isEmpty) {
        return const VoiceResult.cancelled();
      }
      return VoiceResult.heard(heard.trim());
    } on MissingPluginException {
      return const VoiceResult.problem(VoiceProblem.unavailable);
    } on PlatformException catch (error) {
      return VoiceResult.problem(
        error.code == 'no_app' ? VoiceProblem.unavailable : VoiceProblem.failed,
      );
    } catch (error) {
      if (kDebugMode) debugPrint('Voice: $error');
      return const VoiceResult.problem(VoiceProblem.failed);
    }
  }
}

/// What a spoken sentence says about a transaction.
class SpokenEntry {
  const SpokenEntry({this.amount, this.title, this.type, this.categoryId});

  final double? amount;
  final String? title;

  /// Set only when the words say which it is ("got", "salary", "spent").
  final TransactionType? type;

  /// A category whose name was said.
  final String? categoryId;

  bool get isEmpty => amount == null && (title == null || title!.isEmpty);
}

/// Reads "200 on tea", "spent 1,250 for groceries" or "got 5000 salary".
class SpokenEntryParser {
  const SpokenEntryParser._();

  static const String _nepaliDigits = '०१२३४५६७८९';

  /// Words that only join the amount to what it was for.
  static const Set<String> _filler = <String>{
    'on',
    'for',
    'in',
    'at',
    'to',
    'of',
    'the',
    'a',
    'an',
    'rs',
    'rs.',
    'npr',
    'rupee',
    'rupees',
    'rupaiya',
    'rupiya',
    'रुपैयाँ',
    'रु',
    'रू',
    'मा',
    'को',
    'spent',
    'spend',
    'paid',
    'pay',
    'bought',
    'buy',
    'add',
    'expense',
    'खर्च',
  };

  static const Set<String> _incomeWords = <String>{
    'got',
    'received',
    'receive',
    'earned',
    'earn',
    'income',
    'salary',
    'आम्दानी',
    'तलब',
    'पाएँ',
  };

  static const Set<String> _expenseWords = <String>{
    'spent',
    'spend',
    'paid',
    'pay',
    'bought',
    'buy',
    'expense',
    'खर्च',
  };

  static String _westernDigits(String text) {
    final out = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final index = _nepaliDigits.indexOf(char);
      out.write(index >= 0 ? '$index' : char);
    }
    return out.toString();
  }

  static final RegExp _number = RegExp(r'\d[\d,]*(?:\.\d+)?');

  static SpokenEntry parse(
    String spoken, {
    List<CategoryModel> categories = const <CategoryModel>[],
  }) {
    final text = _westernDigits(spoken).trim();
    if (text.isEmpty) return const SpokenEntry();

    // The first number said is the amount.
    double? amount;
    var rest = text;
    final match = _number.firstMatch(text);
    if (match != null) {
      final value = double.tryParse(match.group(0)!.replaceAll(',', ''));
      if (value != null && value > 0) {
        amount = value;
        rest =
            '${text.substring(0, match.start)} '
            '${text.substring(match.end)}';
      }
    }

    final words = rest
        .split(RegExp(r'\s+'))
        .map((word) => word.replaceAll(RegExp(r'^[^\wऀ-ॿ]+|[^\wऀ-ॿ]+$'), ''))
        .where((word) => word.isNotEmpty)
        .toList();
    final lower = <String>[for (final word in words) word.toLowerCase()];

    TransactionType? type;
    if (lower.any(_incomeWords.contains)) {
      type = TransactionType.income;
    } else if (lower.any(_expenseWords.contains)) {
      type = TransactionType.expense;
    }

    // What is left once the joining words are gone is what it was for.
    // "salary" and the like stay: they are the name of the thing too.
    final kept = <String>[
      for (var i = 0; i < words.length; i++)
        if (!_filler.contains(lower[i]) &&
            !const <String>{
              'got',
              'received',
              'receive',
              'earned',
              'earn',
              'पाएँ',
            }.contains(lower[i]))
          words[i],
    ];
    var title = kept.join(' ').trim();
    if (title.isNotEmpty) {
      title = title[0].toUpperCase() + title.substring(1);
    }

    // A category whose name was said, the longest such name winning.
    String? categoryId;
    var best = 0;
    final said = ' ${lower.join(' ')} ';
    for (final category in categories) {
      final name = category.name.trim().toLowerCase();
      if (name.isEmpty || name.length <= best) continue;
      // An income is not filed under an expense-only category, or the
      // other way round.
      if (type == TransactionType.income &&
          category.kind == CategoryKind.expense) {
        continue;
      }
      if (type == TransactionType.expense &&
          category.kind == CategoryKind.income) {
        continue;
      }
      if (said.contains(' $name ')) {
        categoryId = category.id;
        best = name.length;
      }
    }

    return SpokenEntry(
      amount: amount,
      title: title.isEmpty ? null : title,
      type: type,
      categoryId: categoryId,
    );
  }
}
