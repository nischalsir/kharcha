import '../core/errors/app_failure.dart';
import '../core/utils/id_generator.dart';
import '../models/recurring_payment_model.dart';
import '../models/sync_models.dart';
import '../services/nepali_date_service.dart';
import 'cached_repository.dart';
import 'transaction_repository.dart';

class RecurringPaymentRepository extends CachedRepository<RecurringPayment> {
  RecurringPaymentRepository(
    super.cache,
    super.sync,
    this._transactions,
    this._dates,
  );

  final TransactionRepository _transactions;
  final NepaliDateService _dates;

  @override
  SyncEntity get entity => SyncEntity.recurringTransactions;

  @override
  RecurringPayment parse(Map<String, dynamic> json) {
    return RecurringPayment.fromJson(json);
  }

  @override
  Map<String, dynamic> serialize(RecurringPayment item) => item.toJson();

  List<RecurringPayment> all() {
    final list = readAll()..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    return list;
  }

  RecurringPayment? byId(String id) {
    final row = cache.row(entity, id);
    return row == null ? null : RecurringPayment.fromJson(row);
  }

  List<RecurringPayment> upcoming({int withinDays = 30}) {
    final now = DateTime.now();
    final limit = DateTime(now.year, now.month, now.day + withinDays);
    return all()
        .where((item) => item.isActive && !item.nextDate.isAfter(limit))
        .toList();
  }

  Future<RecurringPayment> save(RecurringPayment item) async {
    if (item.title.trim().isEmpty) {
      throw const AppFailure(FailureKind.invalidData, 'Title is required.');
    }
    if (item.amount <= 0) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Amount must be greater than zero.',
      );
    }
    if (item.frequency == RecurringFrequency.custom &&
        (item.intervalDays ?? 0) < 1) {
      throw const AppFailure(
        FailureKind.invalidData,
        'Custom interval must be at least 1 day.',
      );
    }
    final anchor = item.anchorBsDay ?? _dates.toBs(item.startDate).day;
    final saved = item.copyWith(
      title: item.title.trim(),
      anchorBsDay: () => anchor,
      updatedAt: DateTime.now(),
    );
    await write(saved);
    return saved;
  }

  Future<RecurringPayment> create({
    required String title,
    required double amount,
    required RecurringFrequency frequency,
    required DateTime startDate,
    required RecurringPayment template,
  }) {
    final now = DateTime.now();
    final day = DateTime(startDate.year, startDate.month, startDate.day);
    return save(
      template.copyWith(
        id: newId(),
        title: title,
        amount: amount,
        frequency: frequency,
        startDate: day,
        nextDate: day,
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

  Future<RecurringPayment?> setActive(String id, {required bool active}) async {
    final item = byId(id);
    if (item == null) return null;
    final updated = item.copyWith(isActive: active, updatedAt: DateTime.now());
    await write(updated);
    return updated;
  }

  Future<RecurringPayment?> skipOnce(String id) async {
    final item = byId(id);
    if (item == null) return null;
    return _advance(item);
  }

  Future<RecurringPayment?> markPaid(String id, {DateTime? paidAt}) async {
    final item = byId(id);
    if (item == null) return null;
    final when = paidAt ?? DateTime.now();
    await _transactions.create(
      title: item.title,
      amount: item.amount,
      type: item.type,
      occurredAt: when,
      categoryId: item.categoryId,
      paymentMethod: item.paymentMethod,
      notes: item.notes,
      recurringId: item.id,
    );
    return _advance(item, lastPaidAt: when);
  }

  Future<RecurringPayment> _advance(
    RecurringPayment item, {
    DateTime? lastPaidAt,
  }) async {
    final next = item.nextAfter(item.nextDate, _dates);
    final finished = item.endDate != null && next.isAfter(item.endDate!);
    final updated = item.copyWith(
      nextDate: next,
      isActive: finished ? false : item.isActive,
      lastPaidAt: lastPaidAt != null ? () => lastPaidAt : null,
      updatedAt: DateTime.now(),
    );
    await write(updated);
    return updated;
  }
}
