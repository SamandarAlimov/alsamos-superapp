# Alsamos Store Release Checklist

## Code Status

- Android application id: `com.alsamos.app`
- App display name: `Alsamos`
- Version source: `pubspec.yaml`
- Runtime Supabase config is validated before initialization.
- Local release check: `.\tool\release_check.ps1`

## Manual Before Submission

- Create `android/key.properties` and upload Play App Signing key.
- Build Android release: `flutter build appbundle --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
- Prepare Play Store listing: icon, screenshots, feature graphic, privacy policy URL, support email.
- Complete Google Play Data Safety for auth, media, contacts, location, calls, notifications.
- Configure Android notification channel and FCM credentials when push backend is enabled.
- Configure iOS bundle id, signing team, push notification entitlement, camera/mic/location privacy strings.
- Prepare App Store listing: screenshots, privacy nutrition labels, support URL, review notes.
- Prepare Microsoft Store package identity and signing certificate.
- Verify production Supabase RLS with a non-admin test user before release upload.
