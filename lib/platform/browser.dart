// Browser checks; on Android these are all false.
export 'browser_stub.dart' if (dart.library.js_interop) 'browser_web.dart';
