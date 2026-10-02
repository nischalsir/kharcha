/// Splits [total] equally between [people], to the paisa.
///
/// The shares always add up to [total] exactly: when it does not divide
/// evenly the leftover paisa go to the first shares, one each.
List<double> splitEqually(double total, int people) {
  if (people <= 0 || total <= 0) return const <double>[];
  final paisa = (total * 100).round();
  final base = paisa ~/ people;
  final extra = paisa % people;
  return <double>[
    for (var i = 0; i < people; i++) (base + (i < extra ? 1 : 0)) / 100,
  ];
}

/// How a bill the user paid divides between them and their friends.
class BillSplit {
  const BillSplit({required this.mine, required this.friends});

  /// The payer's own part; zero when they paid only for the others.
  final double mine;

  /// What each friend owes, in the order the friends were given.
  final List<double> friends;

  /// Whether every friend owes the same amount.
  bool get isEven =>
      friends.isEmpty || friends.every((share) => share == friends.first);
}

/// Divides [total] between [friends] friends and, when [includePayer] is
/// set, the person who paid.
///
/// With the payer included every friend owes exactly the same, rounded down
/// to the paisa, and the payer absorbs whatever does not divide: nobody is
/// asked for a paisa more than the next person. Without the payer the whole
/// bill has to land on the friends, so the odd paisa go to the first of them.
BillSplit splitBill(
  double total, {
  required int friends,
  required bool includePayer,
}) {
  if (friends <= 0 || total <= 0) {
    return const BillSplit(mine: 0, friends: <double>[]);
  }
  if (!includePayer) {
    return BillSplit(mine: 0, friends: splitEqually(total, friends));
  }
  final paisa = (total * 100).round();
  final each = paisa ~/ (friends + 1);
  return BillSplit(
    mine: (paisa - each * friends) / 100,
    friends: List<double>.filled(friends, each / 100),
  );
}
