# Nupur Beauty Parlour

Management app for Nupur Beauty Parlour (Only for ladies).

## Features

- Dashboard with daily collection, dues, bookings, and customer count
- Customer list with search and add-customer dialog
- Appointment list with add-booking flow
- Billing screen with bill creation and due tracking
- Service price list grouped by category
- Reports screen for sales, collection, dues, and visits
- Settings screen for parlour and owner name

## Run

```powershell
flutter pub get
flutter run
```

## iOS Build

The iOS host project is in `ios/`. Build the iPhone app from macOS with Xcode
installed:

```bash
flutter pub get
cd ios
pod install
cd ..
flutter build ios
```

Then open `ios/Runner.xcworkspace` in Xcode, choose your Apple Developer Team,
set the final bundle identifier, and archive for TestFlight/App Store.

The app already includes iOS privacy descriptions for photos, camera, and
contacts in `ios/Runner/Info.plist`. For Google backup/restore on iOS, keep the
Google iOS reversed client ID in `CFBundleURLSchemes`.

## Google Backup & Restore

The app has Google Drive backup/restore in Settings.

Backup saves customers, services, bookings, bills, and settings into the signed-in
Google account's private Drive app data. Use the same Google account on another
phone and tap restore to move the data.

For release builds, create Google OAuth credentials for the Android package:

- Package name: `com.example.parlour_management_app`
- Add the SHA-1 certificate fingerprint for the signing key used to build the APK
- Enable the Google Drive API in the same Google Cloud project

If you also create a Web OAuth client ID, build with:

```powershell
flutter build apk --release --dart-define=GOOGLE_SIGN_IN_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

Without valid Google OAuth setup, the app still works locally, but Google
backup/restore sign-in can fail.

## Phone Preview Tester

Run the app inside a phone-sized screen in Chrome:

```powershell
flutter run -d chrome --dart-define=PHONE_PREVIEW=true
```

## Test

```powershell
flutter test
```
