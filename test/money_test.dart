import 'package:flutter_test/flutter_test.dart';
import 'package:splitrip/money.dart';

int sum(Map<String, int> m) => m.values.fold(0, (s, v) => s + v);

void main() {
  test('weighted products remain exact beyond native and web int ranges', () {
    const amount = 999999999999;
    final s = splitWeighted(amount, {'b': 999999999999, 'a': 999999999999});
    expect(s, {'a': 500000000000, 'b': 499999999999});
    expect(sum(s), amount);
    final tied = splitWeighted(17, {for (var i = 39; i >= 0; i--) 'p${i.toString().padLeft(2, '0')}': 1});
    expect(tied.entries.where((e) => e.value == 1).map((e) => e.key),
        [for (var i = 0; i < 17; i++) 'p${i.toString().padLeft(2, '0')}']);
  });

  test('equal split puts remainder cents on first sorted ids', () {
    final s = splitEqual(1000, ['c', 'a', 'b']);
    expect(s, {'a': 334, 'b': 333, 'c': 333});
    expect(sum(s), 1000);
  });

  test('weighted split always sums to total', () {
    expect(splitWeighted(1000, {'a': 1, 'b': 1, 'c': 1}), {'a': 334, 'b': 333, 'c': 333});
    expect(splitWeighted(999, {'a': 50, 'b': 25, 'c': 25}), {'a': 499, 'b': 250, 'c': 250});
    for (final amt in [1, 7, 101, 99999]) {
      expect(sum(splitWeighted(amt, {'a': 33, 'b': 33, 'c': 34})), amt);
    }
  });

  test('exact split must match total', () {
    expect(exactSplitValid(1000, {'a': 600, 'b': 400}), isTrue);
    expect(exactSplitValid(1000, {'a': 600, 'b': 399}), isFalse);
  });

  test('balances net to zero and settle-up clears them', () {
    final b = balances(
      ['a', 'b', 'c'],
      [Expense('a', 3000, splitEqual(3000, ['a', 'b', 'c'])), Expense('b', 1000, splitEqual(1000, ['b', 'c']))],
      [const Payment('c', 'a', 500)],
    );
    expect(sum(b), 0);
    final after = {...b};
    for (final p in settleUp(b)) {
      after[p.from] = after[p.from]! + p.amount;
      after[p.to] = after[p.to]! - p.amount;
    }
    expect(after.values.every((v) => v == 0), isTrue);
    expect(settleUp(b).length, lessThanOrEqualTo(2));
  });
}
