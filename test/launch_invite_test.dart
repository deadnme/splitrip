import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitrip/screens/join_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('consumed install invite survives restart but stays scoped to identity and code', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await launchInviteConsumed('first-user', 'ABCD2345'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(launchInviteKey('first-user', 'abcd-2345'), true);
    expect(await launchInviteConsumed('first-user', 'ABCD2345'), isTrue);
    expect(await launchInviteConsumed('new-user', 'ABCD2345'), isFalse);
    expect(await launchInviteConsumed('first-user', 'WXYZ2345'), isFalse);
  });
}
