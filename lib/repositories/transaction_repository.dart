import '../core/errors/app_failure.dart';
import '../core/utils/id_generator.dart';
import '../models/payment_method.dart';
import '../models/sync_models.dart';
import '../models/transaction_model.dart';
import 'cached_repository.dart';

enum TransactionSort { dateDesc, dateAsc, amountDesc, amountAsc }

class TransactionFilter {
  const TransactionFilter({
    this.query = '',
    this.type,
    this.status,
    this.categoryId,
    this.paymentMethod,
    this.from,
    this.toExclusive,
    this.minAmount,
    this.maxAmount,
    this.recurringOnly = false,
    this.sort = TransactionSort.dateDesc,
  });

  final String query;
  final TransactionType? type;
  final TransactionStatus? status;
  final String? categoryId;
  final PaymentMethod? paymentMethod;
  final DateTime? from;
  final DateTime? toExclusive;
  final double? minAmount;
  final double? maxAmount;
  final bool recurringOnly;
  final TransactionSort sort;

  TransactionFilter copyWith({
    String? query,
    TransactionType? Function()? type,
    TransactionStatus? Function()? status,
    String? Function()? categoryId,
    PaymentMethod? Function()? paymentMethod,
    DateTime? Function()? from,
    DateTime? Function()? toExclusive,
    double? Function()? minAmount,
    double? Function()? maxAmount,
    bool? recurringOnly,
    TransactionSort? sort,
  }) {
    return TransactionFilter(
      query: query ?? this.query,
      type: type != null ? type() : this.type,
      status: status != null ? status() : this.status,
      categoryId: categoryId != null ? categoryId() : this.categoryId,
      paymentMethod: paymentMethod != null
          ? paymentMethod()
          : this.paymentMethod,
      from: from != null ? from() : this.from,
      toExclusive: toExclusive != null ? toExclusive() : this.toExclusive,
      minAmount: minAmount != null ? minAmount() : this.minAmount,
      maxAmount: maxAmount != null ? maxAmount() : this.maxAmount,
      recurringOnly: recurringOnly ?? this.recurringOnly,
      sort: sort ?? this.sort,
    );
  }

  bool matches(TransactionModel item) {
    if (type != null && item.type != type) return false;
    if (status != null && item.status != status) return false;
    if (categoryId != null && item.categoryId != categoryId) return false;
    if (paymentMethod != null && item.paymentMethod != paymentMethod) {
      return false;
    }
    if (recurringOnly && item.recurringId == null) return false;
    if (from != null && item.occurredAt.isBefore(from!)) return false;
    if (toExclusive != null && !item.occurredAt.isBefore(toExclusive!)) {
      return false;
    }
    if (minAmount != null && item.amount < minAmount!) return false;
    if (maxAmount != null && item.amount > maxAmount!) return false;
    final needle = query.trim().toLowerCase();
    if (needle.isNotEmpty) {
      final haystack = '${item.title} ${item.notes ?? ''}'.toLowerCase();
      if (!haystack.contains(needle)) return false;
    }
    return true;
  }
}

class TransactionRepository extends CachedRepository<TransactionModel> {
  TransactionRepository(super.cache, super.sync);

  @override
  SyncEntity get entity => SyncEntity.transactions;

  @override
  TransactionModel parse(Map<String, dynamic> json) {
    return TransactionModel.fromJson(json);
  }

  @override
  Map<String, dynamic> serialize(TransactionModel item) => item.toJson();

  /// Newest first. Two rows of the same moment fall back to their ids, which
  /// no two rows share, so the order is the same every time it is asked for.
  /// Without that the sort was free to swap them between one read and the
  /// next, and a row on the edge of a page could show twice or not at all.
  static int _newestFirst(TransactionModel a, TransactionModel b) {
    final byDate = b.occurredAt.compareTo(a.occurredAt);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  }

  List<TransactionModel> all() {
    final list = readAll()..sort(_newestFirst);
    return list;
  }

  TransactionModel? byId(String id) {
    final row = cache.row(entity, id);
    return row == null ? null : TransactionModel.fromJson(row);
  }

  List<TransactionModel> query(
    TransactionFilter filter, {
    int offset = 0,
    int? limit,
  }) {
    final list = readAll().where(filter.matches).toList();
    switch (filter.sort) {
      case TransactionSort.dateDesc:
        list.sort(_newestFirst);
      case TransactionSort.dateAsc:
        list.sort((a, b) {
          final byDate = a.occurredAt.compareTo(b.occurredAt);
          return byDate != 0 ? byDate : a.id.compareTo(b.id);
        });
      case TransactionSort.amountDesc:
        list.sort((a, b) {
          final byAmount = b.amount.compareTo(a.amount);
          return byAmount != 0 ? byAmount : _newestFirst(a, b);
        });
      case TransactionSort.amountAsc:
        list.sort((a, b) {
          final byAmount = a.amount.compareTo(b.amount);
          return byAmount != 0 ? byAmount : _newestFirst(a, b);
        });
    }
    if (offset >= list.length) return <TransactionModel>[];
    final end = limit == null
        ? list.length
        : (offset + limit > list.length ? list.length : offset + limit);
    return list.sublist(offset, end);
  }

  void _validate(TransactionModel item) {
    if (item.title.trim().isEmpty) {
      throw const AppFailure(FailureKind.invalidData, 'Title is required.');
    }
    if (item.amount <= 0) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Amount must be greater than zero.',
      );
    }
    if (item.isTransfer) {
      final to = item.transferTo;
      if (to == null || to == item.paymentMethod) {
        throw const AppFailure(
          FailureKind.invalidData,
          'Choose two different wallets.',
        );
      }
    } else if (item.transferTo != null) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Only a transfer moves money to another wallet.',
      );
    }
  }

  Future<TransactionModel> save(TransactionModel item) async {
    _validate(item);
    final saved = item.copyWith(
      title: item.title.trim(),
      updatedAt: DateTime.now(),
    );
    await write(saved);
    return saved;
  }

  Future<TransactionModel> create({
    required String title,
    required double amount,
    required TransactionType type,
    required DateTime occurredAt,
    TransactionStatus status = TransactionStatus.completed,
    String? categoryId,
    PaymentMethod paymentMethod = PaymentMethod.cash,
    String? notes,
    String? attachmentPath,
    String? recurringId,
    PaymentMethod? transferTo,
    String? id,
  }) {
    final now = DateTime.now();
    return save(
      TransactionModel(
        // A caller that can name the record (a statement import) passes its
        // own id, so writing it twice is one record, not two.
        id: id ?? newId(),
        title: title,
        amount: amount,
        type: type,
        status: status,
        categoryId: categoryId,
        paymentMethod: paymentMethod,
        occurredAt: occurredAt,
        notes: notes,
        attachmentPath: attachmentPath,
        recurringId: recurringId,
        transferTo: transferTo,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> delete(String id) async {
    final item = byId(id);
    if (item == null) return;
    final now = DateTime.now();
    await write(item.copyWith(deletedAt: () => now, updatedAt: now));
  }

  Future<TransactionModel?> duplicate(String id) async {
    final item = byId(id);
    if (item == null) return null;
    final now = DateTime.now();
    return save(
      TransactionModel(
        id: newId(),
        title: item.title,
        amount: item.amount,
        type: item.type,
        status: item.status,
        categoryId: item.categoryId,
        paymentMethod: item.paymentMethod,
        occurredAt: now,
        notes: item.notes,
        // The receipt belongs to the original; a copy starts without one.
        transferTo: item.transferTo,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Moves [amount] from one wallet to another. Recorded as one transaction,
  /// so it shows in the history without counting as spending or income.
  Future<TransactionModel> createTransfer({
    required PaymentMethod from,
    required PaymentMethod to,
    required double amount,
    required DateTime occurredAt,
    String? notes,
  }) {
    return create(
      title: '${from.label} to ${to.label}',
      amount: amount,
      type: TransactionType.transfer,
      occurredAt: occurredAt,
      paymentMethod: from,
      transferTo: to,
      notes: notes,
    );
  }
}
