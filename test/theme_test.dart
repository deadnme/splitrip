import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitrip/theme.dart';

void main() {
  testWidgets('follows the system until toggled, then remembers the choice', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await loadThemeChoice();
    themeT = makeThemeController(tester);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: ThemeToggle()))));
    expect(themeT.value, 1); // nothing saved: system is dark

    // Nothing saved yet: the phone switching light/dark carries the app along.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    followSystem();
    await tester.pumpAndSettle();
    expect(themeT.value, 0);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    followSystem();
    await tester.pumpAndSettle();
    expect(themeT.value, 1);

    await tester.tap(find.byType(ThemeToggle));
    await tester.pump(); // ticker starts
    await tester.pump(const Duration(milliseconds: 200));
    expect(themeT.value, inExclusiveRange(0, 1)); // mid-fade, not a jump
    await tester.pumpAndSettle();
    expect(themeT.value, 0);
    expect((await SharedPreferences.getInstance()).getString('theme'), 'light');

    // A saved choice beats the system from now on.
    followSystem();
    await tester.pumpAndSettle();
    expect(themeT.value, 0);
    themeT.dispose();
  });
}
