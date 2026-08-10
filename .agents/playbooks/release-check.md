# Release Check Playbook

Use for final verification or store-release tasks.

## Commands

```powershell
dart analyze
flutter test
flutter build windows --debug
flutter build apk --debug
```

For production release, use existing scripts first:

```powershell
powershell -ExecutionPolicy Bypass -File tool/release_check.ps1
```

## Notes

- Do not stage build artifacts.
- If Android build needs network for Gradle dependencies, rerun with the
  approved network-capable environment in the main agent session.
- Report manual store steps separately: signing keys, store assets, push certs.

