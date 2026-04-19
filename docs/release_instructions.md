# Release Instructions

## Android Signed Debug APK

1. Create/verify debug keystore (default Android debug keystore is acceptable for assessment).
2. Build:
   - `flutter build apk --debug`
3. Artifact:
   - `build/app/outputs/flutter-apk/app-debug.apk`
4. Install on a clean physical Android device and verify:
   - anonymous identity generated
   - short code shown
   - transfer send/receive works

## iOS Build

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select real iPhone target (or one real + one emulator pairing per brief).
3. Build and run signed for development profile.
4. Preferred: archive and upload to TestFlight, then invite `[HIRING_EMAIL]`.
5. If TestFlight is not possible: provide unsigned build + exact Xcode run steps in submission notes.

## Submission Package

- Installable build(s).
- Source zip or public GitHub link.
- README with architecture + edge-case honesty.
- 5-8 minute walkthrough video.
