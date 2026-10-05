import 'package:flutter_test/flutter_test.dart';
import 'package:splitrip/db.dart';
import 'package:splitrip/main.dart';

void main() {
  test('invite links and codes round-trip', () {
    expect(codeFromInvite(inviteLink('RZ6NGDYZ')), 'RZ6NGDYZ');
    expect(codeFromInvite('rz6n-gdyz'), 'RZ6NGDYZ');
    expect(codeFromInvite('https://splitrip-5fde9.web.app/join/rz6ngdyz?x=1'), 'RZ6NGDYZ');
    expect(joinCodeFromRoute('/join/RZ6NGDYZ'), 'RZ6NGDYZ');
    expect(joinCodeFromRoute('https://splitrip-5fde9.web.app/join/RZ6NGDYZ'), 'RZ6NGDYZ');
    expect(joinCodeFromRoute('/'), isNull);
    expect(joinCodeFromRoute(null), isNull);
  });
}
