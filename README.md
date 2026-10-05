# SpliTrip

Split trip expenses with friends. Flutter app for Android and the web (installable as a PWA on iPhone), backed by Firebase (Firestore + anonymous auth).

- Web: https://splitrip-5fde9.web.app
- Android: `com.splitrip.app`

## Features

- Trips shared by an 8-character invite code, QR code or `/join/CODE` link (Android App Link; opens the web app otherwise)
- Equal, exact, percent and shares splits. All money is integer minor units (`lib/money.dart`)
- Balances and suggested settle-up transfers. Amounts are shown rounded: owed amounts round up, amounts to get back round down, with the exact value underneath
- Random Pay wheel with physics (`lib/wheel_physics.dart`)
- PDF trip summary
- Offline cache via Firestore persistence; iOS web uses long polling

## Develop

```sh
flutter pub get
flutter analyze
flutter test
```

Firestore rules tests (needs Java for the emulator):

```sh
cd tools/rules-test && npm install && cd ../..
firebase emulators:exec --only firestore --project demo-splitrip "node tools/rules-test/test.mjs"
```

## Build and release

```sh
flutter build apk --release --split-per-abi   # needs android/key.properties + android/upload-keystore.jks (not in git)
flutter build web --release
firebase deploy --only hosting --project splitrip-5fde9
firebase deploy --only firestore:rules --project splitrip-5fde9
```

The release signing key is not in this repository. Every APK update must be signed with the same key, or users have to uninstall, which wipes their login.
