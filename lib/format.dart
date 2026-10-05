// Currency display, money text parsing, local dates. Pure Dart, no doubles.
import 'package:intl/intl.dart';

const currencies = [
  'PHP', 'USD', 'EUR', 'GBP', 'JPY', 'KRW', 'THB', 'AUD', 'CAD',
  'NZD', 'SGD', 'MYR', 'IDR', 'VND', 'INR', 'CHF', 'HKD',
];

/// Minor-unit digits for an ISO currency (JPY 0, PHP 2, ...).
int currencyDigits(String code) => NumberFormat.simpleCurrency(name: code).decimalDigits ?? 2;

String currencySymbol(String code) => NumberFormat.simpleCurrency(name: code).currencySymbol;

int _pow10(int d) {
  var p = 1;
  for (var i = 0; i < d; i++) {
    p *= 10;
  }
  return p;
}

/// "1,234.50" for 123450 minor units with 2 digits.
String formatPlain(int minor, int digits, {bool grouping = true}) {
  final p = _pow10(digits);
  final a = minor.abs();
  final whole = grouping ? NumberFormat('#,##0').format(a ~/ p) : '${a ~/ p}';
  final frac = digits > 0 ? '.${(a % p).toString().padLeft(digits, '0')}' : '';
  return '${minor < 0 ? '-' : ''}$whole$frac';
}

/// "₱1,234.50". With [code] true: "PHP 1,234.50" (for the PDF's Latin-1 font).
String formatMoney(int minor, String currency, {bool code = false}) {
  final s = formatPlain(minor.abs(), currencyDigits(currency));
  final sign = minor < 0 ? '-' : '';
  return code ? '$sign$currency $s' : '$sign${currencySymbol(currency)}$s';
}

/// How a whole-number display amount is rounded. Display only: every amount
/// is stored and calculated in exact minor units.
/// Rule: what someone owes or pays rounds up, what someone gets back rounds
/// down (nobody comes up short); neutral totals round to nearest.
enum Rounding { up, down, nearest }

/// Minor units in one whole currency unit (100 for PHP, 1 for JPY).
int wholeUnit(String currency) => _pow10(currencyDigits(currency));

/// [minor] rounded to whole units, still in minor units (13334 up -> 13400).
int roundWhole(int minor, String currency, Rounding r) {
  final u = wholeUnit(currency);
  final a = minor.abs();
  final w = switch (r) {
        Rounding.up => (a + u - 1) ~/ u,
        Rounding.down => a ~/ u,
        Rounding.nearest => (a + u ~/ 2) ~/ u,
      } *
      u;
  return minor < 0 ? -w : w;
}

/// True when the amount has no cents, so there's no exact value to show.
bool isWhole(int minor, String currency) => minor % wholeUnit(currency) == 0;

/// "₱134" for 13334 rounded up. With [code] true: "PHP 134" (PDF font).
String formatWhole(int minor, String currency, Rounding r, {bool code = false}) {
  final w = roundWhole(minor, currency, r) ~/ wholeUnit(currency);
  final s = formatPlain(w.abs(), 0);
  final sign = w < 0 ? '-' : '';
  return code ? '$sign$currency $s' : '$sign${currencySymbol(currency)}$s';
}

final _num = RegExp(r'^(\d*)(?:\.(\d*))?$');

/// Parses user text like "12.5" into minor units (1250 for 2 digits).
/// Returns null for empty/invalid text or more decimals than allowed.
int? parseMinor(String text, int digits) {
  final t = text.trim().replaceAll(',', '');
  final m = _num.firstMatch(t);
  if (m == null) return null;
  final whole = m.group(1) ?? '';
  final frac = m.group(2) ?? '';
  if (whole.isEmpty && frac.isEmpty) return null;
  if (frac.length > digits) return null;
  return (whole.isEmpty ? 0 : int.parse(whole)) * _pow10(digits) +
      (frac.isEmpty ? 0 : int.parse(frac.padRight(digits, '0')));
}

/// Today's date in the device's local time zone, as yyyy-MM-dd.
String todayLocal() => DateFormat('yyyy-MM-dd').format(DateTime.now());
