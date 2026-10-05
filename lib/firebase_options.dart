// PLACEHOLDER. This file will be overwritten by:
//   flutterfire configure --project=splitrip-5fde9 --platforms=android,web
// Until then the app compiles, but Firebase.initializeApp fails at runtime
// because apiKey/appId are empty.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('DefaultFirebaseOptions are not supported for this platform.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBbJg1y1blPyvTeR8zAowoFZNk6QiOgpPc',
    appId: '1:339365658690:web:820b3bf9251f4719cd6ddb',
    messagingSenderId: '339365658690',
    projectId: 'splitrip-5fde9',
    authDomain: 'splitrip-5fde9.firebaseapp.com',
    storageBucket: 'splitrip-5fde9.firebasestorage.app',
    measurementId: 'G-PTEF2WKECE',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDb9fItJXNWTGogAQhKkbnMCDJqjI0ht2A',
    appId: '1:339365658690:android:527416f75936dfcdcd6ddb',
    messagingSenderId: '339365658690',
    projectId: 'splitrip-5fde9',
    storageBucket: 'splitrip-5fde9.firebasestorage.app',
  );
}
