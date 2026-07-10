# Alsamos Store Release Checklist

This project is configured to present the app name as `Alsamos` on Android, iOS, macOS, Windows, Linux, and web.

## Shared

- App display name: `Alsamos`
- Version source: `pubspec.yaml` (`version: 1.0.1+2`)
- Main app icon assets are already present for Android, iOS, web, Windows, and Linux.
- Before every store build, run:

```powershell
flutter clean
flutter pub get
flutter doctor -v
```

## Android - Google Play

- Display name is set in `android/app/src/main/AndroidManifest.xml`.
- Application id is currently `com.alsamos.alsamos_flutter`.
- Release signing reads `android/key.properties` when present.
- Keep these files out of git:
  - `android/key.properties`
  - `android/app/*.jks`
  - `android/app/*.keystore`

Create an upload keystore, then create `android/key.properties` with:

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=app/upload-keystore.jks
```

Build Play Store artifact:

```powershell
flutter build appbundle --release
```

Output:

```text
build/app/outputs/bundle/release/app-release.aab
```

## iOS - App Store

- Display name is `Alsamos`.
- Bundle identifier is `com.alsamos.Alsamos`.
- Product bundle is `Alsamos.app`.
- Final archive/sign/upload requires macOS, Xcode, an Apple Developer team, and matching provisioning profiles.

Build on macOS:

```bash
flutter build ipa --release
```

## macOS - Mac App Store

- Product name is `Alsamos`.
- Bundle identifier is `com.alsamos.Alsamos`.
- Product bundle is `Alsamos.app`.
- Final signing/notarization/upload requires macOS, Xcode, Apple Developer certificates, and App Store provisioning.

Build on macOS:

```bash
flutter build macos --release
```

## Windows - Microsoft Store

- Window title is `Alsamos`.
- Executable name is `Alsamos.exe`.
- Windows version metadata uses product name `Alsamos`.
- Microsoft Store packaging still needs MSIX packaging, publisher identity, signing certificate, and Store association.

Build Windows artifact:

```powershell
flutter build windows --release
```

## Linux

- Window title is `Alsamos`.
- Binary name is `Alsamos`.
- GTK application id is `com.alsamos.Alsamos`.
- Store distribution needs a target package format such as Snap, Flatpak, AppImage, deb, or rpm.

Build on Linux:

```bash
flutter build linux --release
```

## Web

- PWA manifest name and short name are `Alsamos`.
- HTML title and mobile web app title are `Alsamos`.

Build web:

```powershell
flutter build web --release
```
