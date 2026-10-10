import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'db.dart';
import 'firebase_options.dart';
import 'platform/browser.dart';
import 'screens/install_screen.dart';
import 'screens/join_screen.dart';
import 'screens/loading.dart';
import 'screens/trips_screen.dart';
import 'theme.dart';

Future<void> main() async {
  // Web: read real paths like /join/CODE instead of #/ hashes. No-op elsewhere.
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Offline cache: on by default on Android, off by default on web, so set it.
  // iOS WebKit can hold back Firestore's streamed responses (new listeners took
  // 20-30s on an iPhone), so iOS web uses plain long polling instead.
  // ?lp=0 / ?lp=1 overrides it, for comparing.
  final lp = urlParam('lp');
  FirebaseFirestore.instance.settings = Settings(
    persistenceEnabled: true,
    webExperimentalForceLongPolling: lp == null ? isIosWeb : lp == '1',
  );
  await loadThemeChoice();
  runApp(const SpliTripApp());
}

class SpliTripApp extends StatefulWidget {
  const SpliTripApp({super.key});

  @override
  State<SpliTripApp> createState() => _SpliTripAppState();
}

class _SpliTripAppState extends State<SpliTripApp> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    themeT = makeThemeController(this);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangePlatformBrightness() => followSystem();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    themeT.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: themeT,
        builder: (context, _) {
          final theme = themeAt(themeT.value);
          return MaterialApp(
            title: 'SpliTrip',
            scaffoldMessengerKey: messengerKey,
            // Our own controller animates the theme; the built-in tween would
            // chase it every frame.
            theme: theme,
            themeAnimationStyle: AnimationStyle.noAnimation,
            // Android nav bar matches the page instead of staying black.
            builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                systemNavigationBarColor: theme.colorScheme.surface,
                systemNavigationBarIconBrightness: themeT.value < 0.5 ? Brightness.dark : Brightness.light,
              ),
              child: child!,
            ),
            // Cold start, possibly from an invite link (Android App Link or web URL).
            onGenerateInitialRoutes: (route) => [MaterialPageRoute(builder: (_) => SignInGate(joinCode: joinCodeFromRoute(route)))],
            // Invite link opened while the app is already running.
            onGenerateRoute: (s) {
              final code = joinCodeFromRoute(s.name);
              return code == null ? null : MaterialPageRoute(builder: (_) => JoinScreen(initialCode: code));
            },
          );
        },
      );
}

/// "/join/ABCD2345" (with or without host/query) -> "ABCD2345".
String? joinCodeFromRoute(String? route) {
  final m = RegExp(r'^/join/([A-Za-z0-9-]+)').firstMatch(Uri.tryParse(route ?? '')?.path ?? '');
  return m == null ? null : normalizeCode(m.group(1)!);
}

/// The first launch needs the network once for anonymous sign-in; after that
/// the saved session works offline. Shows a retry screen instead of hanging.
class SignInGate extends StatefulWidget {
  /// Set when the app was opened from an invite link: join once signed in.
  final String? joinCode;
  const SignInGate({super.key, this.joinCode});

  @override
  State<SignInGate> createState() => _SignInGateState();
}

class _SignInGateState extends State<SignInGate> {
  late Future<void> _signIn = _ensureSignedIn();

  Future<void> _ensureSignedIn() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously().timeout(const Duration(seconds: 15));
    }
    fire(resumePendingDeletions());
    final code = widget.joinCode;
    if (code != null && isIosWeb && !isIosBrowserTab && await launchInviteConsumed(uid, code)) return;
    if (code != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) {
          if (!mounted) return;
          Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => isIosBrowserTab ? InstallFirstScreen(code: code) : JoinScreen(initialCode: code),
          ),
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _signIn,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(body: Loading('Signing in…'));
          }
          if (snap.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.wifi_off, size: 48),
                    const SizedBox(height: 16),
                    const Text('SpliTrip needs internet the first time you open it.', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() => _signIn = _ensureSignedIn()),
                      child: const Text('Retry'),
                    ),
                  ]),
                ),
              ),
            );
          }
          return const TripsScreen();
        },
      );
}
