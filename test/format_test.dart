import 'package:flutter_test/flutter_test.dart';
import 'package:splitrip/db.dart' show newInviteCode, normalizeCode;
import 'package:splitrip/format.dart';

void main() {
  test('parseMinor turns text into int minor units', () {
    expect(parseMinor('12.5', 2), 1250);
    expect(parseMinor('1,234.56', 2), 123456);
    expect(parseMinor('.05', 2), 5);
    expect(parseMinor('7', 0), 7);
    expect(parseMinor('0.1', 0), isNull); // JPY has no decimals
    expect(parseMinor('1.234', 2), isNull);
    expect(parseMinor('', 2), isNull);
    expect(parseMinor('abc', 2), isNull);
    expect(parseMinor('0.1', 2) ! + parseMinor('0.2', 2)!, parseMinor('0.3', 2)); // no float drift
  });

  test('formatMoney uses currency digits', () {
    expect(formatMoney(123450, 'PHP', code: true), 'PHP 1,234.50');
    expect(formatMoney(-5, 'USD', code: true), '-USD 0.05');
    expect(formatMoney(1000, 'JPY', code: true), 'JPY 1,000');
  });

  test('whole-number display: owes rounds up, gets back rounds down', () {
    // The user's examples.
    expect(formatWhole(13333, 'PHP', Rounding.up, code: true), 'PHP 134');
    expect(formatWhole(12966, 'PHP', Rounding.up, code: true), 'PHP 130');
    expect(formatWhole(15555, 'PHP', Rounding.down, code: true), 'PHP 155');
    expect(formatWhole(15555, 'PHP', Rounding.nearest, code: true), 'PHP 156');
    expect(formatWhole(123400, 'PHP', Rounding.up, code: true), 'PHP 1,234'); // already whole: unchanged
    expect(formatWhole(1500, 'JPY', Rounding.up, code: true), 'JPY 1,500'); // no decimals to round
    expect(isWhole(13300, 'PHP'), isTrue);
    expect(isWhole(13333, 'PHP'), isFalse);
    expect(roundWhole(-13333, 'PHP', Rounding.up), -13400);
  });

  test('invite codes are 8 unambiguous chars', () {
    for (var i = 0; i < 200; i++) {
      final c = newInviteCode();
      expect(c, matches(RegExp(r'^[A-HJKMNP-Z2-9]{8}$')));
    }
    expect(normalizeCode(' k7pq-2mxa '), 'K7PQ2MXA');
  });
}
