// Money math for SpliTrip. All amounts are int minor units (cents); never doubles.

/// Splits [amount] evenly across [ids]. Leftover cents go one each to the
/// first ids in sorted order, so every device computes the same result.
Map<String, int> splitEqual(int amount, List<String> ids) {
  if (ids.isEmpty) throw ArgumentError('no participants');
  final sorted = [...ids]..sort();
  final base = amount ~/ sorted.length;
  final extra = amount - base * sorted.length;
  return {for (var i = 0; i < sorted.length; i++) sorted[i]: base + (i < extra ? 1 : 0)};
}

/// Splits [amount] proportionally to [weights] (percentages or share counts)
/// using the largest-remainder method, so the parts always sum to [amount].
Map<String, int> splitWeighted(int amount, Map<String, int> weights) {
  final ids = weights.keys.where((k) => weights[k]! > 0).toList()..sort();
  if (ids.isEmpty) throw ArgumentError('no positive weights');
  final total = ids.fold<BigInt>(BigInt.zero, (s, k) => s + BigInt.from(weights[k]!));
  final out = <String, int>{};
  final rems = <String, BigInt>{};
  var given = 0;
  for (final k in ids) {
    final exact = BigInt.from(amount) * BigInt.from(weights[k]!);
    out[k] = (exact ~/ total).toInt();
    rems[k] = exact % total;
    given += out[k]!;
  }
  // Explicitly break ties by id; List.sort does not promise stability.
  final byRem = [...ids]..sort((a, b) {
    final byRemainder = rems[b]!.compareTo(rems[a]!);
    return byRemainder == 0 ? a.compareTo(b) : byRemainder;
  });
  for (var i = 0; i < amount - given; i++) {
    out[byRem[i]] = out[byRem[i]]! + 1;
  }
  return out;
}

/// True when exact per-person amounts add up to the expense total.
bool exactSplitValid(int amount, Map<String, int> parts) =>
    parts.values.every((v) => v >= 0) && parts.values.fold<int>(0, (s, v) => s + v) == amount;

class Expense {
  final String paidBy;
  final int amount;
  final Map<String, int> splits;
  const Expense(this.paidBy, this.amount, this.splits);
}

class Payment {
  final String from, to;
  final int amount;
  const Payment(this.from, this.to, this.amount);
}

/// Net balance per person: positive = is owed money, negative = owes money.
Map<String, int> balances(Iterable<String> people, Iterable<Expense> expenses, Iterable<Payment> payments) {
  final b = {for (final p in people) p: 0};
  void add(String id, int v) => b[id] = (b[id] ?? 0) + v;
  for (final e in expenses) {
    add(e.paidBy, e.amount);
    e.splits.forEach((id, owed) => add(id, -owed));
  }
  for (final p in payments) {
    add(p.from, p.amount);
    add(p.to, -p.amount);
  }
  return b;
}

/// Suggested transfers that settle every balance: greedy, largest debtor pays
/// largest creditor. At most n-1 transfers.
// ponytail: greedy is not always the minimum transfer count (that's NP-hard); fine for trip-sized groups.
List<Payment> settleUp(Map<String, int> balances) {
  final debtors = balances.entries.where((e) => e.value < 0).map((e) => MapEntry(e.key, -e.value)).toList();
  final creditors = balances.entries.where((e) => e.value > 0).map((e) => MapEntry(e.key, e.value)).toList();
  int byAmount(MapEntry<String, int> a, MapEntry<String, int> b) =>
      b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key);
  final out = <Payment>[];
  while (debtors.isNotEmpty && creditors.isNotEmpty) {
    debtors.sort(byAmount);
    creditors.sort(byAmount);
    final d = debtors.first, c = creditors.first;
    final x = d.value < c.value ? d.value : c.value;
    out.add(Payment(d.key, c.key, x));
    debtors[0] = MapEntry(d.key, d.value - x);
    creditors[0] = MapEntry(c.key, c.value - x);
    debtors.removeWhere((e) => e.value == 0);
    creditors.removeWhere((e) => e.value == 0);
  }
  return out;
}
