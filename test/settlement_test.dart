import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitrip/db.dart';
import 'package:splitrip/screens/trip_screen.dart';

// ignore: subtype_of_sealed_class
class _Doc extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  final String id;
  final Map<String, dynamic> values;
  _Doc(this.id, this.values);
  @override
  Map<String, dynamic> data() => values;
}

TripData tripWithDebts(int amount) => TripData()
  ..trip = Trip(_Doc('trip', {'currency': 'PHP'}))
  ..people = [
    for (final id in ['a', 'b', 'c']) Person(_Doc(id, {'name': id})),
  ]
  ..expenses = [
    for (final payer in ['a', 'b'])
      ExpenseDoc(
        _Doc(payer, {
          'paidBy': payer,
          'amount': amount,
          'splits': {'c': amount},
        }),
      ),
  ];

void main() {
  test('fractional transfers can settle an outstanding whole-unit debt', () {
    final d = tripWithDebts(60);
    expect(d.shownBalances, {'a': 60, 'b': 60, 'c': -120});
    expect(d.transfers.map((t) => t.amount), [60, 60]);
    for (final t in d.transfers) {
      expect(d.shownBalances[t.from], isNot(0));
      expect(d.shownBalances[t.to], isNot(0));
    }
  });

  test('only sub-unit balances continue to count as settled', () {
    final d = tripWithDebts(40);
    expect(d.shownBalances.values, everyElement(0));
    expect(d.transfers, isEmpty);
  });
}
