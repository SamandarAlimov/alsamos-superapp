# CI: kontrakt tekshiruvi

Bu fayl `socialalsamos/docs/contracts/mini-apps/ci.md` bilan bir xil nusxada saqlanadi.

- web: `bash scripts/check-mini-apps-contract.sh`
- Flutter: `bash scripts/check_mini_apps_contract.sh`

## Flutter uchun workflow

```yaml
name: mini-apps-contract

on:
  push:
    branches: [main]
    paths:
      - 'docs/contracts/mini-apps/**'
      - 'lib/features/miniapps/**'
      - 'test/features/miniapps/**'
  pull_request:
    paths:
      - 'docs/contracts/mini-apps/**'
      - 'lib/features/miniapps/**'
      - 'test/features/miniapps/**'

jobs:
  contract:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/check_mini_apps_contract.sh
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter test test/features/miniapps
      - run: |
          flutter analyze \
            lib/features/miniapps/domain \
            lib/features/miniapps/data/mini_app_feed_item.dart \
            lib/features/miniapps/data/mini_apps_feed_repository.dart \
            lib/features/miniapps/presentation/providers/mini_apps_feed_provider.dart
```

## Versiyani ko'tarish tartibi

1. `socialalsamos` da shartnoma o'zgartiriladi va `CONTRACT_VERSION` ko'tariladi.
2. `types.ts` dagi `MINI_APP_CONTRACT_VERSION` yangilanadi.
3. Shu papka `alsamos-superapp` ga aynan ko'chiriladi.
4. Ikkala repoda CI yashil bo'lgandan keyin merge qilinadi.
