/// Any iPhone/iPad browser or Home Screen web app.
bool get isIosWeb => false;

/// Query parameter from the page URL (web only).
String? urlParam(String name) => null;

/// True in an iPhone/iPad Safari tab, i.e. not opened from the Home Screen.
bool get isIosBrowserTab => false;
