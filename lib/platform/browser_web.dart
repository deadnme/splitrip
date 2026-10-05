import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Any iPhone/iPad browser or Home Screen web app (all iOS browsers are WebKit).
bool get isIosWeb {
  final nav = web.window.navigator;
  final ua = nav.userAgent;
  // iPadOS reports itself as a Mac; touch points give it away.
  return RegExp('iPhone|iPad|iPod').hasMatch(ua) || (ua.contains('Macintosh') && nav.maxTouchPoints > 1);
}

/// Query parameter from the page URL, e.g. `?lp=0`.
String? urlParam(String name) => Uri.base.queryParameters[name];

/// True in an iPhone/iPad Safari tab, i.e. not opened from the Home Screen.
/// iOS keeps a tab's storage separate from the Home Screen app's, so trips
/// joined in the tab don't show up in the installed app.
bool get isIosBrowserTab {
  if (!isIosWeb) return false;
  final nav = web.window.navigator;
  final legacyStandalone = (nav as JSObject).getProperty<JSBoolean?>('standalone'.toJS)?.toDart ?? false;
  final standalone = web.window.matchMedia('(display-mode: standalone)').matches;
  return !legacyStandalone && !standalone;
}
