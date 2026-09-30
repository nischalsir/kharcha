enum SyncStatus {
  loadingFromCache('Loading from cache'),
  syncing('Syncing'),
  synced('Synced'),
  offline('Offline'),
  failed('Sync failed');

  const SyncStatus(this.label);

  final String label;
}

enum SyncEntity {
  categories('categories'),
  paymentMethods('payment_methods'),
  appSettings('app_settings', conflictColumn: 'user_id'),
  friends('friends'),
  friendCredits('friend_credits'),
  friendPayments('friend_payments'),
  pasals('pasals'),
  pasalCredits('pasal_credits'),
  pasalCreditItems('pasal_credit_items'),
  pasalPayments('pasal_payments'),
  recurringTransactions('recurring_transactions'),
  transactions('transactions'),
  budgets('budgets');

  const SyncEntity(this.table, {this.conflictColumn = 'id'});

  final String table;
  final String conflictColumn;

  static const String settingsRecordId = 'settings';

  static const Set<String> _readOnlyColumns = <String>{
    'server_updated_at',
    'remaining_amount',
    'total_price',
  };

  static SyncEntity? fromTable(String? table) {
    for (final entity in SyncEntity.values) {
      if (entity.table == table) return entity;
    }
    return null;
  }

  String recordId(Map<String, dynamic> row) {
    if (this == SyncEntity.appSettings) return settingsRecordId;
    return row['id'] as String;
  }

  Map<String, dynamic> fromRemote(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.from(row);
    if (this == SyncEntity.appSettings) {
      copy['id'] = settingsRecordId;
    }
    return copy;
  }

  Map<String, dynamic> toRemote(Map<String, dynamic> row, String? userId) {
    final copy = Map<String, dynamic>.from(row)
      ..removeWhere((key, _) => _readOnlyColumns.contains(key));
    if (this == SyncEntity.appSettings) {
      copy.remove('id');
      if (userId != null) copy['user_id'] = userId;
    } else {
      copy.remove('user_id');
    }
    return copy;
  }
}

class PendingOperation {
  const PendingOperation({
    required this.entity,
    required this.recordId,
    required this.payload,
    required this.createdAt,
    this.revision = 1,
    this.attempts = 0,
    this.lastError,
    this.failed = false,
  });

  final SyncEntity entity;
  final String recordId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int revision;
  final int attempts;
  final String? lastError;
  final bool failed;

  String get key => '${entity.table}:$recordId';

  static PendingOperation? tryFromJson(Map<String, dynamic> json) {
    final entity = SyncEntity.fromTable(json['entity'] as String?);
    final recordId = json['record_id'] as String?;
    final payload = json['payload'];
    if (entity == null || recordId == null || payload is! Map) return null;
    return PendingOperation(
      entity: entity,
      recordId: recordId,
      payload: Map<String, dynamic>.from(payload),
      createdAt:
          DateTime.tryParse((json['created_at'] as String?) ?? '') ??
          DateTime.now(),
      revision: (json['revision'] as num?)?.toInt() ?? 1,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      lastError: json['last_error'] as String?,
      failed: (json['failed'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'entity': entity.table,
      'record_id': recordId,
      'payload': payload,
      'created_at': createdAt.toIso8601String(),
      'revision': revision,
      'attempts': attempts,
      'last_error': lastError,
      'failed': failed,
    };
  }

  PendingOperation copyWith({
    Map<String, dynamic>? payload,
    int? revision,
    int? attempts,
    String? Function()? lastError,
    bool? failed,
  }) {
    return PendingOperation(
      entity: entity,
      recordId: recordId,
      payload: payload ?? this.payload,
      createdAt: createdAt,
      revision: revision ?? this.revision,
      attempts: attempts ?? this.attempts,
      lastError: lastError != null ? lastError() : this.lastError,
      failed: failed ?? this.failed,
    );
  }
}
