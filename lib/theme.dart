import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _seed = Color(0xFF4F46E5);
// Built once: seed-scheme generation is too slow to repeat every frame.
final lightTheme = ThemeData(colorSchemeSeed: _seed);
final darkTheme = ThemeData(colorSchemeSeed: _seed, brightness: Brightness.dark);
const themeCurve = Curves.easeInOutCubic;

/// 0 = light, 1 = dark. The app lerps between the two themes along it.
late AnimationController themeT;

/// preserve: the fade still plays when the phone has system animations off
/// (Flutter would otherwise cut it to 5%). It is a colour fade, which stays
/// comfortable for people who turn motion down.
AnimationController makeThemeController(TickerProvider vsync) => AnimationController(
  vsync: vsync,
  value: _isDark(_saved) ? 1 : 0,
  duration: const Duration(milliseconds: 450),
  animationBehavior: AnimationBehavior.preserve,
);

ThemeData themeAt(double t) => ThemeData.lerp(lightTheme, darkTheme, themeCurve.transform(t));

SharedPreferences? _prefs;
String? _saved; // 'light' / 'dark' once the user has picked; null = follow the system

/// Call before runApp so the first frame already has the right theme.
Future<void> loadThemeChoice() async {
  try {
    _prefs = await SharedPreferences.getInstance();
    _saved = _prefs!.getString('theme');
  } catch (_) {
    // Storage unavailable (e.g. a locked-down browser): just follow the system.
  }
}

bool _isDark(String? choice) => choice == null
    ? SchedulerBinding.instance.platformDispatcher.platformBrightness == Brightness.dark
    : choice == 'dark';

/// Where the theme is heading, so a tap mid-fade reverses it.
bool get goingDark => themeT.status.isForwardOrCompleted;

void _animate(bool dark) => dark ? themeT.forward() : themeT.reverse();

void toggleTheme() {
  final dark = !goingDark;
  _animate(dark);
  _saved = dark ? 'dark' : 'light';
  _prefs?.setString('theme', _saved!);
}

/// The phone switched light/dark: follow it unless the user picked a theme.
void followSystem() {
  if (_saved == null) _animate(_isDark(null));
}

/// Green for money coming back: dark enough on white, light enough on the
/// dark surface. Fades with the theme.
Color gainColor(BuildContext context) {
  Theme.of(context); // rebuild along with the theme fade
  return Color.lerp(const Color(0xFF15803D), const Color(0xFF4ADE80), themeCurve.transform(themeT.value))!;
}

/// Moon in light mode, sun in dark mode. Driven by the same controller as the
/// theme, so the icon turns exactly as fast as the colours change.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: themeT,
    builder: (context, _) {
      final t = themeCurve.transform(themeT.value);
      // One icon fades out before the other fades in, so they never overlap.
      Widget icon(IconData data, double shown, double turn) => Opacity(
        opacity: shown.clamp(0, 1),
        child: Transform.rotate(
          angle: turn * pi / 2,
          child: Transform.scale(scale: 0.75 + 0.25 * shown.clamp(0, 1), child: Icon(data)),
        ),
      );
      return IconButton(
        tooltip: goingDark ? 'Switch to light mode' : 'Switch to dark mode',
        onPressed: toggleTheme,
        icon: Stack(
          children: [icon(Icons.dark_mode_outlined, 1 - 2 * t, -t), icon(Icons.light_mode_outlined, 2 * t - 1, 1 - t)],
        ),
      );
    },
  );
}
